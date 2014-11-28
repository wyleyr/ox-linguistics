;;;;
;;;; ox-linguistics.el
;;;; Org mode export backend that supports linguistics examples
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
  :translate-alist '((plain-list . org-linguistics-plain-list)
		     (item . org-linguistics-item)
		     (paragraph . org-linguistics-paragraph)))

;;
;; General-purpose helpers
;; 
(defun org-linguistics-find-enclosing-pkg (element)
  "Find the enclosing linguistics package of a (list) element during export."
  (let ((pkg (org-export-read-attribute :attr_linguistics element
					:package))
	(parent (org-export-get-parent element)))
	(cond
	 (pkg pkg)
	 (parent (org-linguistics-find-enclosing-pkg parent))
	 (t nil))))

(defmacro package-case (expr &rest bodies)
  "(package-case EXPR (PKG-NAME BODY...) ...)

Eval EXPR to a package name and choose among clauses based on
that package name.  Each clause looks like (PKG-NAME BODY...).
EXPR is evaluated and compared against each clause in turn.  When
a comparison succeeds, the corresponding BODY is evaluated. When
PKG-NAME is a string, it is matched against the value of EXPR.
Otherwise, PKG-NAME is treated as a Boolean condition, and the
comparison succeeds if it evaluates to non-nil."
  (let* ((pkg (make-symbol "pkg"))
	 (expanded-bodies
	  (mapcar (lambda (b)
		    (if (stringp (car b))
			`((string= ,pkg ,(car b)) ,@(cdr b))
		      ; allow `t', etc. as PKG-NAME
		      `(,(car b) ,@(cdr b))))
		  bodies)))
    `(let ((,pkg ,expr))
       (cond
	,@expanded-bodies))))

;;
;; Paragraphs
;; 
(defvar org-linguistics-judgment-regexp
  "^[[:space:]]*\\([*?%#\\\\]+\\)[[:space:]]+"
  ; judgments are: sequences of the characters '*', '?', '%', '#' and '\',
  ; with whitespace after them,
  ; and beginning-of-line and possibly whitespace before them
  ; (so as not to match '?' at the end of sentences, in particular)
  "Regular expression to match linguistic judgments in linguistic example lists")

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
	 (enclosing-pkg (org-linguistics-find-enclosing-pkg paragraph))
	 (transcodep (or (and (string= enclosing-pkg "gb4e")
			      (eq parent-type 'item))
			 (and (string= enclosing-pkg "linguex")
			      (eq parent-type 'item)))))
    (if (not transcodep)
	;; leave contents unchanged if we're not an item in an example list
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
	(package-case enclosing-pkg
	 ("gb4e" (org-linguistics-gb4e-paragraph paragraph contents info))
	 ("linguex" (org-linguistics-linguex-paragraph paragraph contents info))
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

;;
;; Plain lists
;; 
(defun org-linguistics-plain-list (plain-list contents info)
  "Transcode a PLAIN-LIST element from Org to Linguistics LaTeX.
CONTENTS is the contents of the list.  INFO is a plist holding
contextual information.

This function simply wraps org-latex-plain-list for most lists.
But it adds the ability to export plain lists as linguistics
examples using list attributes provided via ATTR_LINGUISTICS declarations.

You can set the :package attribute of an Org list to \"gb4e\" or
\"linguex\" to get the appropriate formatting for a gb4e or
linguex example environment in the export output.

You can set the :item-command attribute to set the command used
to introduce examples.  (If you do not specify :item-command, a
package-appropriate default will be used.)  Possible values for
each backend package are listed in
`org-linguistics-gb4e-item-commands',
`org-linguistics-linguex-item-commands', and
`org-linguistics-philex-item-commands'.  Arguments to these
commands can be provided from Org via a tag on the list item.
Individual arguments should be separated by a string that matches
`org-linguistics-command-args-separator'.

When using gb4e, you can also set the :environment attribute to
select the environment used to construct the example list.  (If
you do not specify :environment, \"exe\" will be used as the
default for top-level lists, and \"xlist\" as the default for
nested sublists.)

For example:

#+ATTR_LINGUISTICS: :package gb4e
1) I know /nothing/ about human languages. <<s:I:know-nothing>>
2) * But Ralph do. <<s:ralph:knows>>

will give:
\\begin{exe}
\\ex[ ]{\\label{s:I:know-nothing}I know \\emph{nothing} about human languages.}
\\ex[*]{\\label{s:ralph:knows}But Ralph do.}
\\end{exe}

and

#+ATTR_LINGUISTICS: :package linguex
1) I know /nothing/ about human languages. <<s:I:know-nothing>>
2) * But Ralph do. <<s:ralph:knows>>

will give:
\\ex.\\label{s:I:know-nothing}I know \\emph{nothing} about human languages.
\\par
\\ex.*\\label{s:ralph:knows}But Ralph do.
\\par
"
  (let* ((type (org-element-property :type plain-list))
	 (pkg (org-export-read-attribute :attr_linguistics plain-list :package))
	 (env (org-export-read-attribute :attr_linguistics plain-list :environment))
	 (cmd (org-export-read-attribute :attr_linguistics plain-list :item-command))
	 (enclosing-pkg (org-linguistics-find-enclosing-pkg plain-list)))
    (package-case enclosing-pkg
      ; if this list *itself* has "gb4e" as package, use exe env (or user value)
      ((string= pkg "gb4e")
       (org-linguistics-gb4e-plain-list plain-list contents info (or env "exe")))
      ; if this list is *enclosed in* a gb4e list, use xlist env (or user value)
      ("gb4e" (org-linguistics-gb4e-plain-list plain-list contents info 
					       (or env "xlist")))
      ; the distinction between toplevel and sublevel lists is handled at the
      ; item level for linguex
      ("linguex" (org-linguistics-linguex-plain-list plain-list contents info))
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
	    (or (plist-get (org-export-read-attribute :attr_linguistics plain-list)
			   :options)
		"")
	    contents
	    list-type)))

(defun org-linguistics-linguex-plain-list (plain-list contents info)
  "Transcode a plain list to linguex example."
  ; all commands are handled by org-linguistics-linguex-item
  contents)

;;
;; List items
;; 
(defvar org-linguistics-empty-judgment-placeholder "%%EMPTY-JUDGMENT%%")

(defun org-linguistics-item (item contents info)
  "Transcode an ITEM element from Org to Linguistics LaTeX.
CONTENTS holds the contents of the item.  INFO is a plist holding
contextual information."
  (let* ((parent-list (org-element-property :parent item))
	 (pkg (org-export-read-attribute :attr_linguistics parent-list :package))
	 (enclosing-pkg (org-linguistics-find-enclosing-pkg item)))
    (package-case enclosing-pkg 
      ("gb4e" (org-linguistics-gb4e-item item contents info))
      ("linguex"
       (if (string= pkg "linguex")
           ; toplevel item, to be transcoded as \ex.
	   (org-linguistics-linguex-item item contents info t)
         ; sublist item, to be transcoded as \a. etc.
	 (org-linguistics-linguex-item item contents info nil)))
      (t (org-latex-item item contents info)))))

(defun org-linguistics-gb4e-item (item contents info)
  "Transcode an ITEM element from Org to a gb4e \\ex command"
  (flet ((get-par-child
	  (el)
	  (car ; assumes only one child is a paragraph (this is safe for items) 
	   (remove-if-not
	    (lambda (c) (eq 'paragraph (org-element-type c)))
	    (org-element-contents el)))))
    (let* ((par-child (get-par-child item))
	   (judgment (org-element-property :judgment par-child))
	   (tag (org-element-property :tag item))
	   (item-cmd (if tag (format "\\exi{%s}" (org-export-data tag info))
		       "\\ex")))
     (if judgment
	 (progn
	   (org-element-put-property item :has-judgment t)
	   (format "%s[%s]%s" item-cmd judgment contents))
       (progn
	 (org-element-put-property item :has-judgment nil)
	 (concat item-cmd
		 org-linguistics-empty-judgment-placeholder
		 contents))))))

(defun org-linguistics-linguex-item (item contents info toplevel)
  "Transcode an ITEM element from Org to a linguex example item.
If TOPLEVEL is non-nil, the item will be transcoded as a linguex \\ex. command.
Otherwise, it will transcoded as \\a. or \\b. as appropriate."
  (let* ((start-cmd (cond
		     (toplevel "\\ex.")
		     ((org-export-first-sibling-p item info) "\\a.")
		     (t "\\b.")))
	 (tag (org-element-property :tag item))
	 (tag-cmd (if tag
		      (format "[%s]" (org-export-data tag info))
		    ""))
	 (end-cmd (cond
		   (toplevel "\\par\n")
		   ((org-export-last-sibling-p item info) "\\z.\n")
		   (t "\n"))))
    ; alignment of judgment, etc. handled by org-linguistics-linguex-paragraph 
    (concat start-cmd tag-cmd contents end-cmd)))

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