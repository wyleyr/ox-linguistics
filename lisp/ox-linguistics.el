;;;;
;;;; ox-linguistics.el
;;;; Export backend that supports linguistics examples
;;;;
;;;; Copyright 2014 Richard Lawrence
;;;; This file is free software: you can redistribute it and/or modify
;;;; it under the terms of the GNU General Public License as published by
;;;; the Free Software Foundation, either version 3 of the License, or
;;;; (at your option) any later version.

;;;; This file is distributed in the hope that it will be useful,
;;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;;; GNU General Public License for more details.

;;;; You should have received a copy of the GNU General Public License
;;;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.



(require 'ox-latex)

(org-export-define-derived-backend
 'linguistics
 'latex
 :menu-entry
 '(?d "Export to Linguistics LaTeX"
      ((?L "As LaTeX buffer" org-linguistics-export-as-latex)
       (?l "As LaTeX file" org-linguistics-export-to-latex)
       (?p "As PDF file" org-linguistics-export-to-pdf)
       (?o "As PDF file and open"
	   (lambda (a s v b)
	     (if a (org-latex-export-to-pdf t s v b)
	       (org-open-file (org-latex-export-to-pdf nil s v b)))))))
  :options-alist '((:latex-class "LATEX_CLASS" nil org-latex-default-class t)
		   (:latex-class-options "LATEX_CLASS_OPTIONS" nil nil t)
		   (:latex-header "LATEX_HEADER" nil nil newline)
		   (:latex-header-extra "LATEX_HEADER_EXTRA" nil nil newline)
		   (:latex-hyperref-p nil "texht" org-latex-with-hyperref t)
		   ;; Redefine regular options.
		   (:date "DATE" nil "\\today" t))
  :translate-alist '((plain-list . org-linguistics-plain-list)
		     (item . org-linguistics-item)
		     (paragraph . org-linguistics-paragraph)))

(defun find-enclosing-env (element)
  "Find the enclosing environment of a (list) element during export."
  (let ((type (org-element-property :type element))
	(env (org-export-read-attribute :attr_latex element
					:environment))
	(parent (org-export-get-parent element)))
	(cond
	 (env env)
	 (parent (find-enclosing-env parent))
	 (t nil))))

(defvar org-linguistics-judgment-regexp
  "^[[:space:]]*\\([*?%#\\\\]+\\)[[:space:]]+"
  ; judgments are: sequences of the characters '*', '?', '%', '#' and '\',
  ; with whitespace after them,
  ; and beginning-of-line and possibly whitespace before them
  ; (so as not to match '?' at the end of sentences, in particular)
  "Regular expression to match linguistic judgments in lingustic example lists")

(defvar org-linguistics-label-regexp
  "[[:space:]]*\\(\\\\label{[a-zA-Z0-9_.:-]+}\\)[[:space:]]*"
  ; labels are: '\label{', followed by any non-empty sequence of
  ; allowed label key chars, followed by '}' and possibly whitespace
  "Regular expression to match labels in linguistic example lists")

(defun org-linguistics-paragraph (paragraph contents info)
  "Transcode paragraph, handling paragraphs in linguistic example lists specially.

This function exists to extract judgment and label strings from
paragraphs that occur in linguistics examples, since some
packages need to handle these separately.  For example, linguex
requires that judgment strings immediately follow an \\ex. or
\\a. or \\b. command with no intervening space or label; gb4e
requires judgment strings to be placed in an optional argument to
the \\ex command.  Extracting labels is important because an Org
user may place targets or label commands anywhere in the list
item, but leaving them in-place can cause phantom line breaks in
LaTeX's compiled output (e.g. if they are at the end of the list
item).

In most cases this function just returns CONTENTS unchanged.  But
if PARAGRAPH is the child of an item in an example list, it
extracts the judgment string and label string (if any) from
CONTENTS and stores them in the :judgment and :label properties
of PARAGRAPH, respectively.  The 'proper' contents, i.e., the
contents minus the label and judgment strings, are stored in
PARAGRAPH's :proper-contents property.  This function then calls
the appropriate package-specific paragraph transcoding function."
  (let* ((parent (org-element-property :parent paragraph))
	 (parent-type (org-element-type parent))
	 (enclosing-env (find-enclosing-env paragraph))
	 (transcodep (or (and (string= enclosing-env "gb4e-exe")
			      (eq parent-type 'item))
			 (and (string= enclosing-env "linguex-ex")
			      (eq parent-type 'item)))))
    (if (not transcodep)
	;; leave contents unchanged if we're not an item in a gb4e list
	contents
      ;; otherwise, separate judgments and labels from contents
      ;; proper: labels are removed first, so that judgments end up at
      ;; the beginning of CONTENTS-NO-LABEL (even if they were
      ;; preceded by a label in CONTENTS).  PROPER-CONTENTS is every
      ;; part of CONTENTS-NO-LABEL after the judgment.
      (let* ((label-match (string-match org-linguistics-label-regexp contents))
	     (label (when label-match (match-string 1 contents)))
	     (contents-no-label (apply 'concat
				       (split-string
					contents
					org-linguistics-label-regexp
					t)))
	     (judgment-match (string-match org-linguistics-judgment-regexp
					   contents-no-label))
	     (judgment (when judgment-match (match-string 1 contents-no-label)))
	     (proper-contents (substring contents-no-label
					 (if judgment-match (match-end 0) 0))))
	;; keep extracted values as properties, to be manipulated 
	;; elsewhere if required
	(org-element-put-property paragraph :judgment judgment)
	(org-element-put-property paragraph :label label)
	(org-element-put-property paragraph :proper-contents proper-contents)
	(cond
	 ((string= enclosing-env "gb4e-exe")
	  (org-linguistics-gb4e-paragraph paragraph contents info))
	 ((string= enclosing-env "linguex-ex")
	  (org-linguistics-linguex-paragraph paragraph contents info))
	 (t
	  ; this should not happen, as we won't be in the else branch
	  ; of (if (not transcodep) ...) unless the enclosing env is a
	  ; recognized package
	  (error "Cannot transcode paragraph in unrecognized environment")))))))
  
(defun org-linguistics-gb4e-paragraph (paragraph contents info)
  "Transcode paragraph in a gb4e list item.

This function properly formats gb4e example text and labels,
handling label placement and inserting curly braces as necessary."
  ;; otherwise, separate judgments and labels from contents proper
  (let* ((label (org-element-property :label paragraph))
	 (proper-contents (org-element-property :proper-contents paragraph)))
      (if (string= "" proper-contents)
	    ; empty contents should just get a label and no braces
	    ; because we might be opening a sublist
	  (format "%s" (or label ""))
	; otherwise, label should appear inside braces, at the front.
	; Note that placing the label outside the braces or after the content
	; can cause phantom line breaks.
	(format "{%s%s}" (or label "") proper-contents))))

(defun org-linguistics-linguex-paragraph (paragraph contents info)
  "Transcode paragraph in linguex list item.

This function properly formats linguex example text and labels,
handling judgment and label placement." 
  (let ((judgment (org-element-property :judgment paragraph))
	(label (org-element-property :label paragraph))
	(proper-contents (org-element-property :proper-contents paragraph)))
    ;; judgment must appear before anything else, with nothing
    ;; intervening between \ex. command and judgments, for proper
    ;; alignment
    (format "%s%s%s"
	    (or judgment "")
	    (or label "")
	    proper-contents)))

(defun org-linguistics-plain-list (plain-list contents info)
  "Transcode a PLAIN-LIST element from Org to Linguistics LaTeX.
CONTENTS is the contents of the list.  INFO is a plist holding
contextual information.

This function simply wraps org-latex-plain-list for most lists.
But it adds the ability to export plain lists as linguistics
examples.  You can set the :environment attribute of an Org list to
gb4e-exe or linguex-ex to get the appropriate formatting for a
gb4e or linguex example environment in the export output.

For example:

#ATTR_LATEX: :environment gb4e-exe
1) I know /nothing/ about human languages. <<s:I:know-nothing>>
2) * But Ralph do. <<s:ralph:knows>>

will give:
\\begin{exe}
\\ex[ ]{\\label{s:I:know-nothing}I know \\emph{nothing} about human languages.}
\\ex[*]{\\label{s:ralph:knows}But Ralph do.}
\\end{exe}

and

#ATTR_LATEX: :environment linguex-ex
1) I know /nothing/ about human languages. <<s:I:know-nothing>>
2) * But Ralph do. <<s:ralph:knows>>

will give:
\\ex. \\label{s:I:know-nothing}I know \\emph{nothing} about human languages. \\par
\\ex.* \\label{s:ralph:knows}But Ralph do. \\par
"
  (let* ((type (org-element-property :type plain-list))
	 (env (org-export-read-attribute :attr_latex plain-list :environment))
	 (enclosing-env (find-enclosing-env plain-list)))
    (cond 
      ;; this is a slight abuse of ":environment"
      ;; "gb4e-exe" and "linguex-ex" are not names of LaTeX environments exactly,
      ;; but they make it easy to indicate the intended environment 
     
      ; if this list itself has "gb4e-exe" as environment, use exe env
      ((string= env "gb4e-exe")
       (org-linguistics-gb4e-plain-list plain-list contents info "exe"))
      ; if this list is *enclosed in* a "gb4e-exe" environment, use xlist env
      ((string= enclosing-env "gb4e-exe")
       (org-linguistics-gb4e-plain-list plain-list contents info "xlist"))
      ; the distinction between toplevel and sublevel lists is handled at the
      ; item level for linguex
      ((string= enclosing-env "linguex-ex")
       (org-linguistics-linguex-plain-list plain-list contents info))
      (t (org-latex-plain-list plain-list contents info)))))

(defun org-linguistics-gb4e-plain-list (plain-list contents info list-type)
  "Transcode a plain list to gb4e example.
LIST-TYPE indicates environment type: e.g., 'exe' or 'xlist'"
  (let* ((children-have-judgments-p
	  (remove-if-not
	   (lambda (i) (org-element-property :has-judgment i))
	   (org-element-contents plain-list))))
    (setq contents
     ;; replace empty judgment placeholder with appropriate string, depending
     ;; on whether any items in the list have judgments 
     (with-temp-buffer
       (insert contents)
       (goto-char (point-min))
       (while (search-forward org-linguistics-empty-judgment-placeholder nil t)
	 (if children-have-judgments-p
	     ; TODO: There is an undealt-with corner case here, namely:
	     ; when an empty item is part of a list where other items have
	     ; judgments.  In that case, either don't insert [ ] or *also*
	     ; insert {} so as not to get a runaway argument
	     (replace-match "[ ]" nil t)
	   (replace-match "")))
       (buffer-string)))
    (format "\\begin{%s}%s\n%s\\end{%s}"
	    list-type
	    (or (plist-get (org-export-read-attribute :attr_latex plain-list)
			   :options)
		"")
	    contents
	    list-type)))

(defun org-linguistics-linguex-plain-list (plain-list contents info)
  "Transcode a plain list to linguex example."
  ; all commands are handled by org-linguistics-linguex-item
  contents)

(defun org-linguistics-item (item contents info)
  "Transcode an ITEM element from Org to Linguistics LaTeX.
CONTENTS holds the contents of the item.  INFO is a plist holding
contextual information."
  (let* ((parent-list (org-element-property :parent item))
	 (env (org-export-read-attribute :attr_latex parent-list :environment))
	 (enclosing-env (find-enclosing-env item)))
    (cond 
      ((string= enclosing-env "gb4e-exe")
       (org-linguistics-gb4e-item item contents info))
      ((string= env "linguex-ex")
       ; toplevel item, to be transcoded as \ex.
       (org-linguistics-linguex-item item contents info t))
      ((string= enclosing-env "linguex-ex")
       ; sublist item, to be transcoded as \a. etc.
       (org-linguistics-linguex-item item contents info nil))
      (t (org-latex-item item contents info)))))

(defvar org-linguistics-empty-judgment-placeholder "%%EMPTY-JUDGMENT%%")
(defun org-linguistics-gb4e-item (item contents info)
  "Transcode an ITEM element from Org to a gb4e \\ex command"
  (labels ((get-par-child
	    (el)
	    (car ; assumes only one child is a paragraph (this is safe for items) 
	     (remove-if-not
	      (lambda (c) (eq 'paragraph (org-element-type c)))
	      (org-element-contents el)))))
    (let* ((par-child (get-par-child item))
	   (judgment (org-element-property :judgment par-child)))
     (if judgment
	 (progn
	   (org-element-put-property item :has-judgment t)
	   (format "\\ex[%s]%s" judgment contents))
       (progn
	 (org-element-put-property item :has-judgment nil)
	 (format "\\ex%s%s" org-linguistics-empty-judgment-placeholder
		 contents))))))

(defun org-linguistics-linguex-item (item contents info toplevel)
  "Transcode an ITEM element from Org to a linguex example item.
If TOPLEVEL is non-nil, the item will be transcoded as a linguex \\ex. command.
Otherwise, it will transcoded as \\a. or \\b. as appropriate."
  (labels ((first-child-p (el)
	    ; an element is the first child of its parent if its :begin
	    ; matches its parent list's :content-begin
	    (let* ((parent (org-element-property :parent el))
		   (el-begin (org-element-property :begin el))
		   (contents-begin (org-element-property :contents-begin parent)))
	      (equal el-begin contents-begin)))
	   (last-child-p (el)
	    ; an element is the last child of its parent if its :end
	    ; matches its parent list's :content-end
	    (let* ((parent (org-element-property :parent el))
		   (el-end (org-element-property :end el))
		   (contents-end (org-element-property :contents-end parent)))
	      (equal el-end contents-end))))
    (let* ((start-cmd (cond
		       (toplevel "\\ex.")
		       ((first-child-p item) "\\a.")
		       (t "\\b.")))
	   (end-cmd (cond
		      (toplevel "\\par\n")
		      ((last-child-p item) "\\z.\n")
		      (t "\n"))))
      ; alignment of judgment, etc. handled by org-linguistics-linguex-paragraph 
      (concat start-cmd contents end-cmd))))

;; Export UI
;; These are merely lightly-customized versions of functions provided in
;; ox-latex.el that provide a UI for the backend defined above
(defun org-linguistics-export-as-latex
  (&optional async subtreep visible-only body-only ext-plist)
  "Export current buffer as a Linguistics LaTeX buffer.

If narrowing is active in the current buffer, only export its
narrowed part.

If a region is active, export that region.

A non-nil optional argument ASYNC means the process should happen
asynchronously.  The resulting buffer should be accessible
through the `org-export-stack' interface.

When optional argument SUBTREEP is non-nil, export the sub-tree
at point, extracting information from the headline properties
first.

When optional argument VISIBLE-ONLY is non-nil, don't export
contents of hidden elements.

When optional argument BODY-ONLY is non-nil, only write code
between \"\\begin{document}\" and \"\\end{document}\".

EXT-PLIST, when provided, is a property list with external
parameters overriding Org default settings, but still inferior to
file-local settings.

Export is done in a buffer named \"*Org LATEX Export*\", which
will be displayed when `org-export-show-temporary-export-buffer'
is non-nil."
  (interactive)
  (org-export-to-buffer 'linguistics "*Org LINGUISTICS LATEX Export*"
    async subtreep visible-only body-only ext-plist (lambda () (LaTeX-mode))))

;;;###autoload
(defun org-linguistics-convert-region-to-latex ()
  "Assume the current region has org-mode syntax, and convert it to
LaTeX using the linguistics backend.  This can be used in any buffer.
For example, you can write an itemized list in org-mode syntax in an
LaTeX buffer and use this command to convert it."
  (interactive)
  (org-export-replace-region-by 'linguistics))

;;;###autoload
(defun org-linguistics-export-to-latex
  (&optional async subtreep visible-only body-only ext-plist)
  "Export current buffer to a Linguistics LaTeX file.

If narrowing is active in the current buffer, only export its
narrowed part.

If a region is active, export that region.

A non-nil optional argument ASYNC means the process should happen
asynchronously.  The resulting file should be accessible through
the `org-export-stack' interface.

When optional argument SUBTREEP is non-nil, export the sub-tree
at point, extracting information from the headline properties
first.

When optional argument VISIBLE-ONLY is non-nil, don't export
contents of hidden elements.

When optional argument BODY-ONLY is non-nil, only write code
between \"\\begin{document}\" and \"\\end{document}\".

EXT-PLIST, when provided, is a property list with external
parameters overriding Org default settings, but still inferior to
file-local settings."
  (interactive)
  (let ((outfile (org-export-output-file-name ".tex" subtreep)))
    (org-export-to-file 'linguistics outfile
      async subtreep visible-only body-only ext-plist)))

;;;###autoload
(defun org-linguistics-export-to-pdf
  (&optional async subtreep visible-only body-only ext-plist)
  "Export current buffer to Linguistics LaTeX then process through to PDF.

If narrowing is active in the current buffer, only export its
narrowed part.

If a region is active, export that region.

A non-nil optional argument ASYNC means the process should happen
asynchronously.  The resulting file should be accessible through
the `org-export-stack' interface.

When optional argument SUBTREEP is non-nil, export the sub-tree
at point, extracting information from the headline properties
first.

When optional argument VISIBLE-ONLY is non-nil, don't export
contents of hidden elements.

When optional argument BODY-ONLY is non-nil, only write code
between \"\\begin{document}\" and \"\\end{document}\".

EXT-PLIST, when provided, is a property list with external
parameters overriding Org default settings, but still inferior to
file-local settings.

Return PDF file's name."
  (interactive)
  (let ((outfile (org-export-output-file-name ".tex" subtreep)))
    (org-export-to-file 'linguistics outfile
      async subtreep visible-only body-only ext-plist
      (lambda (file) (org-latex-compile file)))))

(provide 'ox-linguistics)