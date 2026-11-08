;;; sns-roam-test.el --- ert tests for sns-roam  -*- lexical-binding: t; -*-

;; Run with `mise run test'.  A batch Emacs finds org-roam and org-ml only
;; through the packages in the owner's Emacs config.  A later slice may pin
;; them somewhere else.

(require 'ert)
(require 'cl-lib)

(setq package-user-dir (expand-file-name "~/.emacs.d/elpa"))
(unless (file-directory-p package-user-dir)
  (error "sns-roam tests: no packages at %s" package-user-dir))
(package-initialize)

(add-to-list 'load-path
             (expand-file-name "../lisp" (file-name-directory
                                          (or load-file-name buffer-file-name))))
(require 'org-roam)
(require 'org-ml)
(require 'sns-roam-api)

(defconst sns-roam-test--api-file
  (expand-file-name "../lisp/sns-roam-api.el"
                    (file-name-directory
                     (or load-file-name buffer-file-name)))
  "Absolute path of the library under test, fixed when this file loads.")

(defmacro sns-roam-test--with-roam-dir (&rest body)
  "Run BODY with `org-roam-directory' set to a fresh temporary directory.
Deletes the directory afterwards, so no test touches the owner's slipbox."
  (declare (indent 0))
  `(let* ((dir (make-temp-file "sns-roam-test" t))
          (org-roam-directory dir))
     (unwind-protect (progn ,@body)
       (delete-directory dir t))))

(defun sns-roam-test--org-files ()
  "Return the names of the .org files in `org-roam-directory'."
  (directory-files org-roam-directory nil "\\.org\\'"))

(defun sns-roam-test--date ()
  "Return today's date as YYYY-MM-DD."
  (format-time-string "%Y-%m-%d"))

;;; --- sns-roam-meeting-note ---

(ert-deftest sns-roam-meeting-note-carries-todays-date ()
  (sns-roam-test--with-roam-dir
    (let* ((before (sns-roam-test--date))
           (result (sns-roam-meeting-note "alan-smithee-1-1"))
           (after  (sns-roam-test--date))
           (files  (sns-roam-test--org-files))
           (file   (plist-get result :file)))
      (unwind-protect
          (progn
            (should (= 1 (length files)))
            (should (string-match-p "\\`[0-9]\\{14\\}-alan_smithee_1_1\\.org\\'"
                                    (car files)))
            ;; A run that straddles midnight may legitimately carry either date.
            (should (member (plist-get result :title)
                            (list (concat "alan-smithee-1-1 " before)
                                  (concat "alan-smithee-1-1 " after))))
            (with-temp-buffer
              (insert-file-contents file)
              (should (string-match-p
                       (format "^#\\+title: %s$"
                               (regexp-quote (plist-get result :title)))
                       (buffer-string)))
              (should (string-match-p "^:KIND: +fleeting$" (buffer-string)))))
        (let ((buffer (get-file-buffer file)))
          (when buffer
            (kill-buffer buffer)))))))

(ert-deftest sns-roam-meeting-note-rejects-a-blank-series ()
  (sns-roam-test--with-roam-dir
    (let ((err (should-error (sns-roam-meeting-note "   ") :type 'error)))
      (should (equal "sns-roam-meeting-note: empty series name" (cadr err)))
      (should (null (sns-roam-test--org-files))))))

(ert-deftest sns-roam-set-body-keeps-keywords-and-headings ()
  (sns-roam-test--with-roam-dir
    (let ((file (expand-file-name "note.org" org-roam-directory)))
      (with-temp-file file
        (insert ":PROPERTIES:\n:ID: set-body-test\n:KIND: fleeting\n:END:\n"
                "#+title: set body test\n#+filetags: :research:\n\n"
                "Old intro one.\n\nOld intro two.\n\n"
                "* Old section\nOld section paragraph.\n"))
      (unwind-protect
          ;; The roam database is not under test; point the lookup at the file.
          (cl-letf (((symbol-function 'sns-roam--node-file-or-error)
                     (lambda (_id) file)))
            (sns-roam-set-body "set-body-test" "New intro.")
            (let ((text (with-temp-buffer
                          (insert-file-contents file)
                          (buffer-string))))
              (should (string-match-p "^New intro\\.$" text))
              (should (string-match-p "^#\\+filetags: :research:$" text))
              (should (string-match-p "^:KIND: +fleeting$" text))
              (should (string-match-p "^\\* Old section$" text))
              (should (string-match-p "^Old section paragraph\\.$" text))
              (should-not (string-match-p "Old intro" text))))
        (let ((buffer (get-file-buffer file)))
          (when buffer
            (kill-buffer buffer)))))))

(ert-deftest sns-roam-api-declares-its-package-requirements ()
  (let* ((file sns-roam-test--api-file)
         (info (with-temp-buffer
                 (insert-file-contents file)
                 (package-buffer-info)))
         (required (mapcar #'car (package-desc-reqs info))))
    (should (eq 'sns-roam-api (package-desc-name info)))
    (should (member 'org-roam required))
    (should (member 'org-ml required))
    (should (member 'emacs required))
    (should (alist-get :url (package-desc-extras info)))
    (should (alist-get :authors (package-desc-extras info)))))

(provide 'sns-roam-test)
;;; sns-roam-test.el ends here
