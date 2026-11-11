;;; sns-roam-test.el --- ert tests for sns-roam  -*- lexical-binding: t; -*-

;; Run with `mise run test'.  A batch Emacs finds org-roam and org-ml only
;; through the packages in the owner's Emacs config.  A later slice may pin
;; them somewhere else.

(require 'ert)
(require 'cl-lib)

;; `org-roam-db-location' defaults to the owner's database.  Setting it
;; before org-roam loads means its `defcustom' keeps this value, so the
;; default is never the value at any point in the run.
(defconst sns-roam-test--db-directory
  (make-temp-file "sns-roam-test-db" t)
  "Temporary directory that holds the database every test uses.")
(defconst sns-roam-test--db-location
  ;; The file must not exist yet: org-roam creates its tables only when
  ;; it opens a database file that is absent, and treats an empty one as
  ;; an old version to upgrade.
  (expand-file-name "org-roam.db" sns-roam-test--db-directory)
  "Temporary database file every test in this run uses.")
(setq org-roam-db-location sns-roam-test--db-location)
(add-hook 'kill-emacs-hook
          (lambda ()
            (delete-directory sns-roam-test--db-directory t)))

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
Closes the database connection, then deletes the directory and the
temporary database afterwards, so each test starts with an empty
database and no test touches the owner's slipbox or its database."
  (declare (indent 0))
  `(let* ((dir (make-temp-file "sns-roam-test" t))
          (org-roam-directory dir))
     (unwind-protect (progn ,@body)
       (org-roam-db--close)
       (when (file-exists-p sns-roam-test--db-location)
         (delete-file sns-roam-test--db-location))
       (delete-directory dir t))))

(defun sns-roam-test--kill-file-buffer (file)
  "Kill the buffer visiting FILE, if there is one."
  (let ((buffer (get-file-buffer file)))
    (when buffer
      (kill-buffer buffer))))

(defun sns-roam-test--file-text (file)
  "Return the contents of FILE as a string."
  (with-temp-buffer
    (insert-file-contents file)
    (buffer-string)))

(defun sns-roam-test--register (file text)
  "Write TEXT to FILE and index it in the org-roam database."
  (with-temp-file file
    (insert text))
  (org-roam-db-update-file file))

(defun sns-roam-test--all-rows ()
  "Return an alist of each database table name and all its rows."
  (mapcar (lambda (schema)
            (let ((table (car schema)))
              (cons table (org-roam-db-query [:select * :from $i1] table))))
          org-roam-db--table-schemata))

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

(ert-deftest sns-roam-library-installs-no-packages-when-loaded ()
  ;; A `use-package ... :ensure t' in a library installs packages while
  ;; package-vc compiles it, and a symbol it leaves in
  ;; `package-selected-packages' crashed the first start on a new machine.
  ;; Dependencies belong in the Package-Requires header.
  (dolist (file (directory-files (file-name-directory sns-roam-test--api-file)
                                 t "\\.el\\'"))
    (with-temp-buffer
      (insert-file-contents file)
      (should-not (re-search-forward ":ensure" nil t)))))

;;; --- sns-roam-create-node registers the node (slice 9) ---

(ert-deftest sns-roam-create-node-new-note-can-be-edited-at-once ()
  ;; S9.1.  A batch on 2026-11-09 failed seven times calling
  ;; `sns-roam-set-body' straight after `sns-roam-create-node' (issue #6).
  (sns-roam-test--with-roam-dir
    (should-not (org-roam-db-query [:select id :from nodes :where (= title $s1)]
                                   "Batch claim"))
    (let* ((created (sns-roam-create-node "Batch claim" "permanent"))
           (file (plist-get created :file)))
      (unwind-protect
          (let ((result (sns-roam-set-body (plist-get created :id)
                                           "The new body.")))
            (should (equal file (plist-get result :file)))
            (let ((text (sns-roam-test--file-text file)))
              (should (string-match-p "^#\\+title: Batch claim$" text))
              (should (string-match-p "^The new body\\.$" text))))
        (sns-roam-test--kill-file-buffer file)))))

(ert-deftest sns-roam-create-node-links-show-as-backlinks-at-once ()
  ;; S9.2
  (sns-roam-test--with-roam-dir
    (sns-roam-test--register
     (expand-file-name "hub.org" org-roam-directory)
     ":PROPERTIES:\n:ID: hub-id\n:END:\n#+title: Hub\n")
    (let* ((body (sns-roam--parse-body-elements
                  "Spoke builds on [[id:hub-id][Hub]]."))
           (spoke (sns-roam-create-node "Spoke" "permanent" body))
           (edges (plist-get (sns-roam-expand "hub-id") :edges)))
      (should (cl-some (lambda (edge)
                         (and (eq :backward (plist-get edge :direction))
                              (equal (plist-get spoke :id)
                                     (plist-get edge :source-id))))
                       edges)))))

(ert-deftest sns-roam-create-node-refusal-leaves-file-and-rows-alone ()
  ;; A row for a file that was not written would make a later lookup of
  ;; the ID resolve to the wrong note.
  (sns-roam-test--with-roam-dir
    (let* ((time (date-to-time "2026-01-01 09:00:00"))
           (path (expand-file-name
                  (concat (sns-roam--filename-prefix-of time)
                          "-overwrite_target.org")
                  org-roam-directory))
           (read-bytes (lambda ()
                         (with-temp-buffer
                           (insert-file-contents-literally path)
                           (buffer-string)))))
      (sns-roam-test--register
       path ":PROPERTIES:\n:ID: existing-id\n:END:\n#+title: Existing note\n")
      (let ((bytes-before (funcall read-bytes))
            (rows-before (sns-roam-test--all-rows)))
        (let ((err (should-error (sns-roam-create-node "Overwrite target"
                                                       "permanent" nil
                                                       "new-id" nil time)
                                 :type 'error)))
          (should (equal (format "sns-roam: refusing to overwrite existing file %s"
                                 path)
                         (cadr err))))
        (should (equal bytes-before (funcall read-bytes)))
        (should (equal rows-before (sns-roam-test--all-rows)))
        (should-not (org-roam-db-query [:select id :from nodes :where (= id $s1)]
                                       "new-id"))))))

(ert-deftest sns-roam-create-node-refuses-an-id-another-file-holds ()
  ;; A retried batch can reuse a pre-minted ID with a new timestamped
  ;; filename.  org-roam only warns on the duplicate, so without this
  ;; refusal the ID would keep resolving to the earlier file.
  (sns-roam-test--with-roam-dir
    (let ((earlier (expand-file-name "earlier.org" org-roam-directory)))
      (sns-roam-test--register
       earlier ":PROPERTIES:\n:ID: reused-id\n:END:\n#+title: Earlier note\n")
      (let ((rows-before (sns-roam-test--all-rows))
            (files-before (sns-roam-test--org-files)))
        (let ((err (should-error (sns-roam-create-node "Retried claim"
                                                       "permanent" nil
                                                       "reused-id")
                                 :type 'error)))
          (should (string-match-p
                   "\\`sns-roam: id \"reused-id\" already names .*earlier\\.org"
                   (cadr err))))
        (should (equal files-before (sns-roam-test--org-files)))
        (should (equal rows-before (sns-roam-test--all-rows)))
        (should (file-equal-p earlier
                              (sns-roam--registered-file "reused-id")))))))

(ert-deftest sns-roam-create-node-fails-when-indexing-does-not-register-the-id ()
  ;; Indexing can fail with only a warning, so success must come from
  ;; the ID resolving to the new file, not from the call returning.
  (sns-roam-test--with-roam-dir
    (let ((err (cl-letf (((symbol-function 'org-roam-db-update-file)
                          #'ignore))
                 (should-error (sns-roam-create-node "Unindexed claim"
                                                     "permanent" nil
                                                     "unindexed-id")
                               :type 'error))))
      (should (string-match-p
               "\\`sns-roam: id \"unindexed-id\" resolves to nil after indexing"
               (cadr err))))))

(ert-deftest sns-roam-tests-use-a-temporary-database ()
  ;; The test file sets the location before it loads org-roam, so the
  ;; owner's database is never the value, setup included.
  (should (equal sns-roam-test--db-location org-roam-db-location))
  (should (string-prefix-p (file-truename temporary-file-directory)
                           (file-truename org-roam-db-location)))
  (should-not (equal (file-truename org-roam-db-location)
                     (file-truename
                      (eval (car (get 'org-roam-db-location 'standard-value)))))))

(provide 'sns-roam-test)
;;; sns-roam-test.el ends here
