;;; avyium.el --- Vimium like for Emacs based on avy -*- lexical-binding: t -*-

;; Copyright (C) 2024 Gong Qijian <gongqijian@gmail.com>

;; Author: Gong Qijian <gongqijian@gmail.com>
;; Created: 2024/11/07
;; Homepage: https://github.com/twlz0ne/avyium
;; Keywords: convenience, www, avy, eww, w3m
;; Package-Requires: ((emacs "28.1") (avy "0.5"))
;; Version: 0.0.14
;; Last-Updated: 2024-11-26 12:02:13 +0800
;;           by: Gong Qijian

;; This file is not part of GNU Emacs

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; [Vimium](https://github.com/philc/vimium) like for Emacs based on [avy](https://github.com/abo-abo/avy).

;; ## Requirements

;; - Emacs 28.1+
;; - Avy 0.5+

;; ## Installation

;; - Manual

;; Clone this repository to `/path/to/avyium/`.  Add the following to your configuration file:

;; ``` elisp
;; (add-to-list 'load-path "/path/to/avyium/")
;; (require 'avyium)
;; ```

;; - Quelpa

;; ``` elisp
;; (quelpa '(avyium :fetcher github
;;                  :repo "twlz0ne/avyium"
;;                  :files ("avyium.el")))
;; ```


;;; Code:

(require 'avy)

(defcustom avyium-next-screen-context-lines 0.5
  "Proportion number of lines of continuity when scrolling by screenfuls."
  :type 'number
  :group 'avyium)

(defcustom avyium-next-page-label-regexps '("next\\(?: >\\ page\\)?" "下一页\\(?: →\\)?")
  "A list of regexp to match the label of next page."
  :type 'list
  :group 'avyium)

(defcustom avyium-prev-page-label-regexps '("\\(?:< \\)?previous\\(?: page\\)?" "\\(?:← \\)?上一页")
  "A list of regexp to match the label of previous page."
  :type 'list
  :group 'avyium)

(defcustom avyium-keys
  '(("Navigating the page"
     ("f"  "Open a link in the current buffer"  avyium-goto-link)
     ("F"  "Open a link in a new buffer"        avyium-goto-link-new-buffer)
     ("j"  "Scroll down"                        next-line)
     ("k"  "Scroll up"                          previous-line)
     ("l"  "Scroll right"                       forward-char)
     ("h"  "Scroll left"                        backward-char)
     ("gg" "Scroll to the top of the page"      beginning-of-buffer)
     ("G"  "Scroll to the bottom of the page"   end-of-buffer)
     ;; zH  Scroll all the way to the left
     ;; zL  Scroll all the way to the right
     ;; gs  View page source
     ;; yy  Copy page's info ;; Copy current url
     ("d"  "Scroll a page down"                 avyium-scroll-down)
     ("u"  "Scroll a page up"                   avyium-scroll-up)
     ("r"  "Reload current page"                avyium-reload-page)
     ("gi" "Focus the first visible text box on the page" avyium-goto-first-input-field)
     ;; p   Open the clipboard's URL in the current buffer
     ;; P   Open the clipboard's URL in a new buffer
     ;; gu  Go up the URL hierarchy
     ;; gU  Go to root of current URL hierarchy
     ("]]" "Follow the link labeled next or \">\"" avyium-goto-link-labeled-next)
     ("[[" "Follow the link labeled previous or \"<\"" avyium-goto-link-labeled-previous)
     ;; m   Create a new mark
     )
    ("Using the minibuffer"
     ("o"  "Open URL, bookmark, or history entry"  avyium-open-url)
     ("O"  "Open URL, history, … in a new tab"     avyium-open-url-in-new-buffer)
     ;; b   Open A bookmark
     ;; B   Open A bookmark in a new buffer
     ;; T   Search through open buffers
     ;; ge  Edit the current URL
     ;; gE  Edit the current URL and open in a new buffer
     ;; gn  Toggle styles of vomnibar page
     )

    ("Using find"
     ;; /   Enter find mode
     ;; n   Cycle forward to the next find match
     ;; N   Cycle backward to the previous find match
     )

    ("Navigating history"
     ("H"  "Go back in history"                 avyium-go-back-history)
     ("L"  "Go forward in history"              avyium-go-forward-history)
     ([tab]  "Move point to next link"          avyium-next-url)
     ([backtab] "Move point to previous link"   avyium-previous-url)
     ([return] "Open link at point"             avyium-goto-link-at-point)
     ([(shift return)] "Open link at point in a new buffer" avyium-goto-link-at-point-in-new-buffer))

    ("Help"
     ("?"  "Show help"                          avyium-show-help)))
  "Key definition.")

(defcustom avyium-open-new-buffer-in-other-window nil
  "Whather to open the new buffer in other window."
  :type 'boolean
  :group 'avyium)

;;; Internal variables
(defvar avyium-open-url-in-new-buffer-p nil)


;;; Utils

(defmacro avyium--loop-element (spec &rest body)
  "Loop over element position from SEARCHSTART.

Evaluate BODY with POS of each element located by SEARCHFN and SEARCHARG.  Then
evaluate RESULT to get return value, default nil.

The SEARCHFN should be one of the followings:

- `next-property-change'
- `next-single-property-change'
- `previous-property-change'
- `previous-single-property-change'

The SEARCHARG should be nil or a text property, depends on what the SEARCHFN is.

\(fn (POS SEARCHFN SEARCHSTART SEARCHARG [RESULT]) BODY...)"
  (declare (indent 1) (debug ((symbolp form &optional form) body)))
  (unless (consp spec)
    (signal 'wrong-type-argument (list 'consp spec)))
  (unless (<= 4 (length spec) 5)
    (signal 'wrong-number-of-arguments (list '(4 . 5) (length spec))))
  (pcase-let ((`(,pos ,searchfn ,searchstart ,searcharg ,result) spec))
    `(let ((,pos (or (and (get-text-property ,searchstart ,searcharg) ,searchstart)
                     (funcall ,searchfn ,searchstart ,searcharg))))
       (while ,pos
         ,@body
         (setq ,pos (funcall ,searchfn ,pos ,searcharg)))
       ,result)))

(defmacro avyium--loop-element-visible (spec &rest body)
  "Loop over position of visible element.

Evaluate BODY with POS of each visible element located by `next-property-change'
or `next-single-property-change' if PROP is provided.  Then evaluate RESULT to
get return value, default nil.

\(fn (POS PROP [RESULT]) BODY...)"
  (declare (indent 1) (debug ((symbolp form &optional form) body)))
  (unless (consp spec)
    (signal 'wrong-type-argument (list 'consp spec)))
  (unless (<= 2 (length spec) 3)
    (signal 'wrong-number-of-arguments (list '(2 . 3) (length spec))))
  (let* ((searcharg (cadr spec))
         (searchfn (if searcharg 'next-single-property-change 'next-property-change)))
    (let ((end (make-symbol "end"))
          (beg (make-symbol "beg")))
      `(let* ((,end (window-end (selected-window) t))
              (,beg (window-start))
              (,(car spec) (or (and (get-text-property ,beg ,searcharg) ,beg)
                               (,searchfn ,beg ,searcharg))))
         (while (and ,(car spec) (< ,(car spec) ,end))
           ,@body
           (setq ,(car spec) (,searchfn ,(car spec) ,searcharg)))
         ,@(cdr (cdr spec))))))

(defun avyium--some-element-backward (start prop pred)
  "Search backward for the first element containing property PROP from START.

PRED is a function that takes one argument, the position of an element."
  (let (some)
    (catch 'break
      (avyium--loop-element (pos #'previous-single-property-change start prop some)
        (when (funcall pred pos)
          (throw 'break (setq some pos)))))))

(defun avyium--collect-link (pred &optional prop)
  "Collect links in selected region or visible part of window.

PRED is a function that takes two arguments, the first is the POSITION of the
new link, the second is the COLLECTION of collected links and each of which take
the form (POSITION . WINDOW).

PROP decide how a link will be located, see `avyium--loop-element-visible' for details."
  (let (candidates)
    (avyium--loop-element-visible (pos prop)
      (let ((entry (funcall pred pos candidates)))
        (when entry (push entry candidates))))
    (nreverse candidates)))

(defun avyium--get-scroll-count (count)
  "Given a user-supplied COUNT, return scroll count."
  (cl-flet ((posint (x) (and (natnump x) (< 0 x) x)))
    (or (posint count)
        (posint 0)
        (/ (window-body-height) 2))))


;;; Generics

(cl-defgeneric avyium--links () "Links to be hinted in the visible part of a buffer.")

(cl-defgeneric avyium--follow-link () "Follow the link at point.")

(cl-defgeneric avyium--goto-input-field (n) "Goto the N-th input field.")

(cl-defgeneric avyium--follow-page-link (regexps)
  "Follow the page link that lable matched by REGEXPS.")


;;; Commands

(defun avyium-show-help ()
  "Show help information."
  (interactive)
  (let ((buffer (get-buffer-create "*avyium-keys*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (when (featurep 'page-break-lines)
          (funcall #'page-break-lines-mode 1))
        (insert "Avyium keys\n\n")
        (dolist (key-group avyium-keys)
          (insert ?\^L "\n")
          (insert ";; " (car key-group) "\n\n")
          (mapc (pcase-lambda (`(,key ,desc ,_cmd))
                  (insert (format "%-16s %s\n" key desc)))
                (cdr key-group))
          (insert "\n"))))
    (view-buffer-other-window buffer)))

(defun avyium-goto-first-input-field ()
  "Goto the first input field."
  (interactive)
  (let ((pos (avyium--goto-input-field 1)))
    (if pos
        (avyium--follow-link)
      (message "No input field was found."))))

(defun avyium-goto-link (&optional arg)
  "Jump to a link start in current buffer.

When ARG is 1, jump to lines currently visible, when ARG is 4, negate the window
scope determined by `avy-all-windows'."
  (interactive "p")
  (let (pos)
    (avy-with avyium-goto-link
      (avy-dowindows arg
        (setq pos (avy-process (avyium--links)))))
    (when pos
      (avyium--follow-link))))

(defun avyium-goto-link-new-buffer ()
  "Like `avyium-goto-link' but open url in new buffer."
  (interactive)
  (let ((avyium-open-url-in-new-buffer-p t))
    (call-interactively #'avyium-goto-link)))

(defun avyium-goto-link-at-point ()
  "Open the link at point."
  (interactive)
  (avyium--follow-link))

(defun avyium-goto-link-at-point-in-new-buffer ()
  "Open the link at point in a new buffer."
  (interactive)
  (let ((avyium-open-url-in-new-buffer-p t))
    (avyium--follow-link)))

(defun avyium-scroll-down (count)
  "Scroll the window and the cursor COUNT lines downwards.."
  (interactive "P")
  (setq count (avyium--get-scroll-count count))
  ;; Copied from evil 1.15.0
  (if (<= (point-max) (window-end))
      (vertical-motion count)
    (condition-case nil
        (let ((scroll-preserve-screen-position 'always)
              (last-command (when (eq real-last-command real-this-command)
                              real-last-command)))
          (scroll-up count))
      (:success
       ;; If EOB became visible: Scroll it to the bottom
       (save-excursion
         (goto-char (window-start))
         (vertical-motion (max 0 (- (window-height) 1 scroll-margin)))
         (when (<= (point-max) (point)) (recenter -1))))
      (end-of-buffer (goto-char (point-max)) (recenter -1)))))

(defun avyium-scroll-up (count)
  "Scroll the window and the cursor COUNT lines upwards.."
  (interactive "P")
  (setq count (avyium--get-scroll-count count))
  ;; Copied from evil 1.15.0
  (let ((opoint (point)))
    (condition-case nil
        (let ((scroll-preserve-screen-position 'always)
              (last-command (when (eq real-last-command real-this-command)
                              real-last-command)))
          (scroll-down count))
      (:success
       ;; Redo if `scroll-down' only did partial scroll up to BOB
       (when (<= (window-start) (point-min))
         (goto-char opoint)
         (vertical-motion (- count))))
      (beginning-of-buffer (vertical-motion (- count))))))

(defun avyium-goto-link-labeled-next ()
  "Follow the link labeled next or \">\"."
  (interactive)
  (avyium--follow-page-link avyium-next-page-label-regexps))

(defun avyium-goto-link-labeled-previous ()
  "Follow the link labeled previous or \"<\"."
  (interactive)
  (avyium--follow-page-link avyium-prev-page-label-regexps))

(defvar-local avyium-go-forward-history-function nil "Function to go forward history.")
(defun avyium-go-forward-history ()
  "Call `avyium-go-forward-history-function'."
  (interactive)
  (call-interactively avyium-go-forward-history-function))

(defvar-local avyium-go-back-history-function nil "Function to go back history.")
(defun avyium-go-back-history ()
  "Call `avyium-go-back-history-function'."
  (interactive)
  (call-interactively avyium-go-back-history-function))

(defvar-local avyium-next-url-function nil "Move point to next url.")
(defun avyium-next-url ()
  "Call `avyium-next-url-function'."
  (interactive)
  (call-interactively avyium-next-url-function))

(defvar-local avyium-previous-url-function nil "Move point to previous url.")
(defun avyium-previous-url ()
  "Call `avyium-previous-url-function'."
  (interactive)
  (call-interactively avyium-previous-url-function))

(defvar-local avyium-open-url-function nil "Open url in current buffer.")
(defun avyium-open-url ()
  "Call `avyium-open-url-function'."
  (interactive)
  (call-interactively avyium-open-url-function))

(defvar-local avyium-open-url-in-new-buffer-function nil "Open url in a new buffer.")
(defun avyium-open-url-in-new-buffer ()
  "Call `avyium-open-url-in-new-buffer-function'."
  (interactive)
  (call-interactively avyium-open-url-in-new-buffer-function))

(defvar-local avyium-reload-page-function nil "Reload current page.")
(defun avyium-reload-page ()
  "Call `avyium-reload-page-function'."
  (interactive)
  (call-interactively avyium-reload-page-function))


;;; text edit mode

(defvar-local avyium-text-edit-buffer nil)
(defvar-local avyium-text-edit-context nil)

(defun avyium-fill-string-rectangle (string cols rows)
  "Fill the STRING into a rectangle of COLS x ROWS.

If the actual rows are less than ROWS, fill with blank lines; otherwise, leave
it as it is."
  (with-temp-buffer
    (setq-local fill-column cols)
    (insert string)
    (paragraph-indent-minor-mode)
    (fill-region (point-min) (point-max))
    (let ((lines (mapcar (lambda (line)
                           (string-pad line cols ?\s))
                         (reverse (split-string (buffer-string) "\n")))))
      (dotimes (n (- rows (length lines)))
        (push (string-pad "" cols ?\s) lines))
      (string-join (reverse lines) "\n"))))

(defun avyium-text-edit-commit ()
  "Exit eidting, commit changes."
  (interactive)
  (let ((text (buffer-substring-no-properties (point-min) (point-max)))
        (props (cdr avyium-text-edit-context))
        (bounds (car avyium-text-edit-context)))
    (with-current-buffer avyium-text-edit-buffer
      (put-text-property
       (car bounds) (cdr bounds)
       'eww-form (plist-put props :value (concat "\n" text "\n")))
      (eww-update-field (avyium-fill-string-rectangle
                         text (plist-get props :cols) (plist-get props :rows))))
    (kill-buffer-and-window)))

(defvar avyium-text-edit-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") 'avyium-text-edit-commit)
    (define-key map (kbd "C-c C-k") 'kill-buffer-and-window)
    map)
  "Keymap for `avyium-text-edit-mode'.")

(define-derived-mode avyium-text-edit-mode text-mode "Text edit mode"
  "Major mode for text edit.

\\{avyium-text-edit-mode-map}")


;;; avyium-mode

(defvar avyium-mode-map (make-sparse-keymap))

(define-minor-mode avyium-mode
  "Minor mode to provide features like Vimium."
  :init-value nil
  :group 'avyium
  :global nil
  :lighter " Avyium"
  :keymap avyium-mode-map
  (if avyium-mode
      (mapc (pcase-lambda (`(,key ,_ ,cmd))
              (define-key avyium-mode-map key cmd))
            (apply #'append (mapcar #'cdr avyium-keys)))))


;;; eww

(cl-defmethod avyium--links (&context (major-mode eww-mode))
  (avyium--collect-link
   (lambda (pos collection)
     (let ((inhibit-message t) match)
       (cond
        ((setq match (get-text-property pos 'eww-form))
         (let ((start (cdr (assq :start match))))
           (cons start (get-buffer-window))))
        ((setq match (get-text-property pos 'shr-url))
         (when (or (get-text-property pos 'shr-tab-stop)
                   (memq 'shr-indentation (text-properties-at pos)))
           (cons pos (get-buffer-window))))
        ((setq match (get-text-property pos 'image-url))
         (cons pos (get-buffer-window)))
        (t nil))))
   'face))


(defun avyium-advice-eww--open-url-in-new-buffer (url)
  "Adivce override `eww--open-url-in-new-buffer' to open URL in new window."
  (let ((buffer (if (eq major-mode 'eww-mode) (clone-buffer)
                 (generate-new-buffer "*eww*"))))
    (switch-to-buffer-other-window buffer)
    (with-current-buffer buffer
      (unless (equal url (eww-current-url))
        (eww-mode)
        (eww (if (consp url) (car url) url))))))

(cl-defmethod avyium--follow-link (&context (major-mode eww-mode))
  (if (get-text-property (point) 'follow-link)
      (if avyium-open-url-in-new-buffer-p
          (if avyium-open-new-buffer-in-other-window
              (cl-letf (((symbol-function 'eww--open-url-in-new-buffer)
                         #'avyium-advice-eww--open-url-in-new-buffer))
                (eww-open-in-new-buffer))
            (eww-open-in-new-buffer))
        (eww-follow-link))
    (when-let* ((edit? (get-text-property (point) 'inhibit-read-only))
                (props (get-text-property (point) 'eww-form))
                (type (plist-get props :type)))
      (let* ((beg (eww-beginning-of-field))
             (end (eww-end-of-field))
             (txt ;;(string-trim (buffer-substring-no-properties beg end))
              (plist-get props :value)))
        (cond
         ((string= type "textarea")
          (let ((edit-buffer (get-buffer-create (format "*%s*" type)))
                (src-buffer (current-buffer))
                (rows (count-lines beg end))
                (cols (or (plist-get props :cols)
                          (- (save-excursion (goto-char end) (current-column))
                             (save-excursion (goto-char beg) (current-column))))))
            (with-current-buffer edit-buffer
              (erase-buffer)
              (avyium-text-edit-mode)
              (setq fill-column cols)
              (setq avyium-text-edit-buffer src-buffer)
              (setq avyium-text-edit-context
                    (cons (cons beg end)
                          (plist-put (plist-put props :cols cols) :rows rows)))
              (setq header-line-format
                    (substitute-command-keys
                     "Edit, then exit with `\\[avyium-text-edit-commit]' or abort with `\\[kill-buffer-and-window]'") )
              (auto-fill-mode)
              (paragraph-indent-minor-mode)
              (insert (substring txt 1 -1)) ;; Remove "\n" at both ends.
              (fill-region (point-min) (point-max))
              (switch-to-buffer-other-window edit-buffer))))
         (t
          (let ((new-txt (read-from-minibuffer (concat (upcase type) ": ") txt)))
            (put-text-property beg end 'eww-form (plist-put props :value new-txt))
            (eww-update-field (string-pad new-txt (- end beg) ?\s)))))))))

(cl-defmethod avyium--follow-page-link (regexps &context (major-mode eww-mode))
  (let ((pos
         (avyium--some-element-backward
          (point-max) 'follow-link
          (lambda (pos)
            (if-let* ((button (button-at pos)))
                (string-match-p
                 (concat "^\\(" (string-join regexps "\\|") "\\)$")
                 (button-label button)))))))
    (if pos
        (save-excursion
          (goto-char pos)
          (avyium--follow-link))
      (message "No pagination link was found."))))

(cl-defmethod avyium--goto-input-field (n &context (major-mode eww-mode))
  (let ((i n)
        (poss))
    (catch 'break
      (avyium--loop-element-visible (pos 'help-echo)
        (when (equal "Input field" (get-text-property pos 'help-echo))
          (push pos poss)
          (when (zerop (setq i (1- i)))
            (throw 'break t)))))
    (when (zerop i)
      (goto-char (car poss)))))

(defun avyium-setup-eww ()
  "Setup avyium for eww."
  (setq avyium-reload-page-function             #'eww-reload)
  (setq avyium-open-url-function                #'eww)
  (setq avyium-open-url-in-new-buffer-function
        (lambda (url)
          (interactive
           (let ((uris (eww-suggested-uris)))
             (list (read-string (format-prompt
                                 "[New buffer] Enter URL or keywords"
                                 (and uris (car uris)))
                                nil 'eww-prompt-history uris))))
          (eww url t)))
  (setq avyium-go-back-history-function         #'eww-back-url)
  (setq avyium-go-forward-history-function      #'eww-next-url)
  (setq avyium-previous-url-function            #'shr-previous-link)
  (setq avyium-next-url-function                #'shr-next-link)
  (avyium-mode))

(with-eval-after-load 'eww
  (add-hook 'eww-mode-hook #'avyium-setup-eww))


;;; w3m

(cl-defmethod avyium--links (&context (major-mode w3m-mode))
  (avyium--collect-link
   (lambda (pos collection)
     (let ((inhibit-message t) match)
       (cond
        ((setq match (get-text-property pos 'w3m-form-field-id))
         (cons pos (get-buffer-window)))
        ((setq match (get-text-property pos 'w3m-href-anchor))
         (cons pos (get-buffer-window)))
        ((setq match (get-text-property pos 'w3m-image))
         (cons pos (get-buffer-window)))
        (t nil))))
   'face))

(cl-defmethod avyium--follow-link (&context (major-mode w3m-mode))
  (if (get-text-property (point) 'w3m-href-anchor)
      (if avyium-open-url-in-new-buffer-p
          (if avyium-open-new-buffer-in-other-window
              (cl-letf (((symbol-function 'switch-to-buffer)
                         #'switch-to-buffer-other-window))
                (w3m-view-this-url-new-session))
            (w3m-view-this-url-new-session))
        (w3m-view-this-url))
    (let ((props (text-properties-at (point))))
      (when (memq 'w3m-form-field-id props))
      (let ((prop-readonly (memq 'w3m-form-readonly props)))
        (if (and prop-readonly (not (cadr prop-readonly)))
            (w3m-view-this-url)
          (widget-button-press (point)))))))

(cl-defmethod avyium--follow-page-link (regexps &context (major-mode w3m-mode))
  (let ((pos
         (avyium--some-element-backward
          (point-max) 'w3m-href-anchor
          (lambda (pos)
            (if-let* ((end (next-single-property-change pos 'w3m-href-anchor))
                      (lable (buffer-substring-no-properties pos end)))
                (string-match-p
                 (concat "^\\(" (string-join regexps "\\|") "\\)$")
                 lable))))))
    (if pos
        (save-excursion
          (goto-char pos)
          (avyium--follow-link))
      (message "No pagination link was found."))))

(cl-defmethod avyium--goto-input-field (n &context (major-mode w3m-mode))
  (let ((i n)
        (poss))
    (catch 'break
      (avyium--loop-element-visible (pos 'w3m-form-field-id)
        (when (eq 'w3m-form-input (car (get-text-property pos 'w3m-action)))
          (push pos poss)
          (when (zerop (setq i (1- i)))
            (throw 'break t)))))
    (when (zerop i)
      (goto-char (car poss)))))

(defun avyium-setup-w3m ()
  "Setup avyium for w3m."
  (setq avyium-reload-page-function             #'w3m-reload-this-page)
  (setq avyium-open-url-function                #'w3m-goto-url)
  (setq avyium-open-url-in-new-buffer-function  #'w3m-goto-url-new-session)
  (setq avyium-go-back-history-function         #'w3m-view-previous-page)
  (setq avyium-go-forward-history-function      #'w3m-view-next-page)
  (setq avyium-previous-url-function            #'w3m-previous-anchor)
  (setq avyium-next-url-function                #'w3m-next-anchor)
  (when avyium-open-new-buffer-in-other-window
    (w3m-display-mode 'plain))
  (avyium-mode))

(with-eval-after-load 'w3m
  (add-hook 'w3m-mode-hook #'avyium-setup-w3m))

(provide 'avyium)

;;; avyium.el ends here
