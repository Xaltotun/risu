;;; risu.el --- A major mode for editing RISU files
;;
;;; Commentary:
;;
;; This is manly a simple mode for doing syntax highlighting in RISU files
;;
;;; Code:

;; Mode variables
(defvar risu-mode-hook nil
  "Hook run when we enter `risu-mode'")

(defvar risu-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "\C-j" 'newline-and-indent)
    map)
  "Keymap for risu major mode")

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.risu\\'" . risu-mode))

;; Syntax higlighting
(defvar risu-font-lock-keywords
  (list
   '("^#.*$" . font-lock-comment-face)
   '("^[^#! \n]+" . font-lock-type-face)
   '("^[^#! \n]+ +\\([^ ]+\\)" 1 font-lock-constant-face)
   '("\\w+:[0-9]+" . font-lock-variable-name-face)
   '(" \\([01][01 ]+[01]\\)" . font-lock-string-face)
   '("^!constraints" . font-lock-warning-face)
   '("^!memory" . font-lock-warning-face))
  "Minimal highlighting expressions for risu mode")

(defvar risu-mode-syntax-table
  (let ((st (make-syntax-table)))
    (modify-syntax-entry ?_ "w" st)
    st)
  "Syntax table for risu-mode")

;;; Code

(define-derived-mode risu-mode fundamental-mode "RISU"
  "Major mode for editing RISU control files."
  (set (make-local-variable 'font-lock-defaults) '(risu-font-lock-keywords)))

(provide 'risu)
;;; rise.el ends here
