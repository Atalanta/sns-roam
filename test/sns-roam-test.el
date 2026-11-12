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

(defvar sns-roam-test--raised nil
  "Where `sns-roam-test--error-data' records what it asserts, or nil.
`sns-roam-test--raised-by-suite' binds it to a cons whose car is the
name of the test now running and whose cdr collects one entry per
assertion: (TEST-NAME KIND DATA), DATA made portable by
`sns-roam-test--portable'.  When nil, nothing is recorded.")

(defun sns-roam-test--portable (value)
  "Return VALUE with what differs between runs replaced by placeholders.
In every string, the test's `org-roam-directory' becomes <roam>/, a
generated UUID becomes <uuid> and a file name's timestamp prefix
becomes <stamp>, so condition data from two runs compare equal."
  (cond
   ((stringp value)
    (let ((text value))
      (dolist (directory (delete-dups
                          (list (file-name-as-directory org-roam-directory)
                                (file-name-as-directory
                                 (file-truename org-roam-directory)))))
        (setq text (string-replace directory "<roam>/" text)))
      (setq text (replace-regexp-in-string
                  "[[:xdigit:]]\\{8\\}\\(?:-[[:xdigit:]]\\{4\\}\\)\\{3\\}-[[:xdigit:]]\\{12\\}"
                  "<uuid>" text t t))
      (replace-regexp-in-string "\\<[0-9]\\{14\\}-" "<stamp>-" text t t)))
   ((consp value)
    (cons (sns-roam-test--portable (car value))
          (sns-roam-test--portable (cdr value))))
   (t value)))

(defun sns-roam-test--error-data (kind thunk)
  "Show that calling THUNK raises condition KIND, and return its data plist.
The data must start with :kind, whose value is KIND.  When
`sns-roam-test--raised' collects, the assertion is recorded there."
  (let ((err (should-error (funcall thunk) :type kind)))
    (should (eq kind (car err)))
    (should (eq :kind (car (cdr err))))
    (should (eq kind (plist-get (cdr err) :kind)))
    (when sns-roam-test--raised
      (push (list (car sns-roam-test--raised)
                  kind
                  (sns-roam-test--portable (cdr err)))
            (cdr sns-roam-test--raised)))
    (cdr err)))

(defun sns-roam-test--should-have (data &rest expected)
  "Show that plist DATA holds each key and value of plist EXPECTED."
  (cl-loop for (key value) on expected by #'cddr
           do (should (plist-member data key))
           do (should (equal value (plist-get data key)))))

;;; --- the error conditions (slice 21) ---

(defconst sns-roam-test--conditions
  '(sns-roam-unknown-id sns-roam-missing-file sns-roam-malformed-note
    sns-roam-no-excerpt-container sns-roam-match-count
    sns-roam-unsupported-element sns-roam-history-layout sns-roam-bad-date
    sns-roam-reparse-mismatch sns-roam-file-exists sns-roam-id-conflict
    sns-roam-index-failure sns-roam-diff-failure sns-roam-bad-tag)
  "Every condition the bridge raises: the slice 21 list, slice 24's and slice 26's.")

(ert-deftest sns-roam-every-condition-is-an-error-with-its-kind ()
  ;; A handler on `error' still catches each one, the data names it, and
  ;; the message the user sees starts with the bridge's prefix.
  (dolist (kind sns-roam-test--conditions)
    (let ((err (condition-case caught
                   (signal kind (list :kind kind :id "some-id"))
                 (error caught))))
      (should (eq kind (car err)))
      (should (memq 'sns-roam-error (get kind 'error-conditions)))
      (should (eq kind (plist-get (cdr err) :kind)))
      (should (equal "some-id" (plist-get (cdr err) :id)))
      (should (string-prefix-p "sns-roam: " (error-message-string err))))))

(ert-deftest sns-roam-reworded-message-leaves-the-data-a-skill-reads ()
  ;; S21.1: the skills act on :kind and :path, so a new wording for the
  ;; message changes nothing they read.
  (sns-roam-test--with-moved-note
    (let ((message (get 'sns-roam-missing-file 'error-message))
          (before-data (cdr (should-error (sns-roam-body-elements id)
                                          :type 'sns-roam-missing-file))))
      (unwind-protect
          (progn
            (put 'sns-roam-missing-file 'error-message
                 "sns-roam: reworded for this test")
            (let ((err (should-error (sns-roam-body-elements id)
                                     :type 'sns-roam-missing-file)))
              (should (equal before-data (cdr err)))
              (should (string-prefix-p "sns-roam: reworded for this test"
                                       (error-message-string err)))))
        (put 'sns-roam-missing-file 'error-message message)))))

(ert-deftest sns-roam-add-context-keeps-kind-first-and-the-raisers-values ()
  (should (equal '(:kind sns-roam-match-count :id "a" :operation op :count 2)
                 (sns-roam--add-context '(:kind sns-roam-match-count :count 2)
                                        '(:id "a" :operation op))))
  (should (equal '(:kind sns-roam-unknown-id :file "f" :id "raised")
                 (sns-roam--add-context '(:kind sns-roam-unknown-id :id "raised")
                                        '(:id "context" :file "f")))))

;;; --- each kind declared once (slice 22) ---

(defconst sns-roam-test--suite-readers
  '(sns-roam-tests-raise-every-declared-kind
    sns-roam-each-site-raises-the-data-slice-21-recorded)
  "The tests that read what the rest of the suite raises.
`sns-roam-test--raised-by-suite' leaves them out of its run, so
neither runs itself.")

(defvar sns-roam-test--suite-raised nil
  "What `sns-roam-test--raised-by-suite' returned, once it has run.")

(defun sns-roam-test--raised-by-suite ()
  "Return (TEST-NAME KIND DATA) for each error the other tests assert.
Runs every sns-roam test but `sns-roam-test--suite-readers', with
nothing printed, once per Emacs.  The outer run still reports each of
those tests, so one that fails there fails where a person sees it.
Inside a running test `ert-running-test' names the outer test, so the
listener records the name of each test as it starts."
  (or sns-roam-test--suite-raised
      (setq sns-roam-test--suite-raised
            (let ((sns-roam-test--raised (list nil)))
              (ert-run-tests `(and "\\`sns-roam-"
                                   (not (member ,@sns-roam-test--suite-readers)))
                             (lambda (event &rest arguments)
                               (when (eq event 'test-started)
                                 (setcar sns-roam-test--raised
                                         (ert-test-name (nth 1 arguments))))))
              (reverse (cdr sns-roam-test--raised))))))

(ert-deftest sns-roam-tests-raise-every-declared-kind ()
  ;; S22.2: a kind that no test raises shows up here by name.
  (let ((raised (mapcar #'cadr (sns-roam-test--raised-by-suite))))
    (should (equal nil (seq-difference sns-roam--error-kinds raised)))))

(defconst sns-roam-test--slice-21-data-file
  (expand-file-name "error-data-slice-21.eld"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "The data each slice 21 test saw raised before slice 22, made portable.
Each entry is (TEST-NAME KIND DATA), recorded by
`sns-roam-test--raised-by-suite' from the hand-written signal sites.")

(defun sns-roam-test--pairs (plist)
  "Return PLIST as a list of (KEY . VALUE) pairs."
  (cl-loop for (key value) on plist by #'cddr collect (cons key value)))

(ert-deftest sns-roam-each-site-raises-the-data-slice-21-recorded ()
  ;; Each site raises the keys and values it did before slice 22.  Only
  ;; their order after :kind may change, so the data compare as sets.
  (let ((recorded (with-temp-buffer
                    (insert-file-contents sns-roam-test--slice-21-data-file)
                    (read (current-buffer))))
        (raised (sns-roam-test--raised-by-suite)))
    (should (= 34 (length recorded)))
    (should (equal nil
                   (seq-remove
                    (lambda (entry)
                      (seq-find
                       (lambda (now)
                         (and (equal (seq-take entry 2) (seq-take now 2))
                              (seq-set-equal-p
                               (sns-roam-test--pairs (nth 2 entry))
                               (sns-roam-test--pairs (nth 2 now)))))
                       raised))
                    recorded)))))

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
    ;; Only a person at M-x meets this, so it is a `user-error'.
    (let ((err (should-error (sns-roam-meeting-note "   ") :type 'user-error)))
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
        (sns-roam-test--should-have
         (sns-roam-test--error-data
          'sns-roam-file-exists
          (lambda ()
            (sns-roam-create-node "Overwrite target" "permanent" nil
                                  "new-id" nil time)))
         :id "new-id" :path path)
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
        (let ((data (sns-roam-test--error-data
                     'sns-roam-id-conflict
                     (lambda ()
                       (sns-roam-create-node "Retried claim" "permanent" nil
                                             "reused-id")))))
          (sns-roam-test--should-have data :id "reused-id")
          (should (file-equal-p earlier (plist-get data :registered)))
          (should (string-suffix-p "-retried_claim.org" (plist-get data :path))))
        (should (equal files-before (sns-roam-test--org-files)))
        (should (equal rows-before (sns-roam-test--all-rows)))
        (should (file-equal-p earlier
                              (sns-roam--registered-file "reused-id")))))))

(ert-deftest sns-roam-create-node-fails-when-indexing-does-not-register-the-id ()
  ;; Indexing can fail with only a warning, so success must come from
  ;; the ID resolving to the new file, not from the call returning.
  (sns-roam-test--with-roam-dir
    (let ((data (cl-letf (((symbol-function 'org-roam-db-update-file)
                           #'ignore))
                  (sns-roam-test--error-data
                   'sns-roam-index-failure
                   (lambda ()
                     (sns-roam-create-node "Unindexed claim" "permanent" nil
                                           "unindexed-id"))))))
      (sns-roam-test--should-have data :id "unindexed-id" :actual nil)
      (should (string-suffix-p "-unindexed_claim.org"
                               (plist-get data :expected))))))

;;; --- sns-roam-create-node separates paragraphs (slice 10) ---

(defun sns-roam-test--text-from-drawer-end (file)
  "Return the text of FILE from its first :END: line to the end.
Comparing from there shows a blank line added after the drawer, after
#+title or before a headline, as well as the spacing between paragraphs."
  (let ((text (sns-roam-test--file-text file)))
    (substring text (string-match "^:END:$" text))))

(ert-deftest sns-roam-create-node-keeps-three-paragraphs-apart ()
  ;; S10.1.  On 2026-11-09 eight notes came out with their paragraphs on
  ;; consecutive lines, which org reads as one paragraph (issue #5).
  (sns-roam-test--with-roam-dir
    (let* ((created (sns-roam-create-node
                     "Probe" "permanent"
                     (list (org-ml-build-paragraph "One.")
                           (org-ml-build-paragraph "Two.")
                           (org-ml-build-paragraph "Three."))))
           (file (plist-get created :file))
           (text (sns-roam-test--file-text file)))
      (should (equal ":END:\n#+title: Probe\nOne.\n\nTwo.\n\nThree.\n"
                     (sns-roam-test--text-from-drawer-end file)))
      (let ((excerpt (sns-roam-excerpt (plist-get created :id)
                                       (1+ (string-match "^Two\\.$" text)))))
        (should (equal "Two." (string-trim (plist-get excerpt :text))))))))

(ert-deftest sns-roam-create-node-keeps-paragraphs-apart-before-a-headline ()
  ;; S10.2
  (sns-roam-test--with-roam-dir
    (let* ((created (sns-roam-create-node
                     "Probe" "permanent"
                     (list (org-ml-build-paragraph "One.")
                           (org-ml-build-paragraph "Two.")
                           (org-ml-build-headline
                            :title '("Head")
                            (org-ml-build-section
                             (org-ml-build-paragraph "Under."))))))
           (file (plist-get created :file)))
      (should (equal ":END:\n#+title: Probe\nOne.\n\nTwo.\n* Head\nUnder.\n"
                     (sns-roam-test--text-from-drawer-end file))))))

(ert-deftest sns-roam-create-node-keeps-extra-space-a-paragraph-asks-for ()
  ;; S10.3
  (sns-roam-test--with-roam-dir
    (let* ((created (sns-roam-create-node
                     "Probe" "permanent"
                     (list (org-ml-build-paragraph :post-blank 2 "One.")
                           (org-ml-build-paragraph "Two."))))
           (file (plist-get created :file)))
      (should (equal ":END:\n#+title: Probe\nOne.\n\n\nTwo.\n"
                     (sns-roam-test--text-from-drawer-end file))))))

(ert-deftest sns-roam-create-node-writes-a-single-paragraph-unchanged ()
  (sns-roam-test--with-roam-dir
    (let* ((created (sns-roam-create-node
                     "Probe" "permanent"
                     (list (org-ml-build-paragraph "One."))))
           (file (plist-get created :file)))
      (should (equal ":END:\n#+title: Probe\nOne.\n"
                     (sns-roam-test--text-from-drawer-end file))))))

;;; --- sns-roam-body-elements (slice 11) ---

(defun sns-roam-test--file-state (file)
  "Return FILE's bytes and modification time, to show a call left it alone."
  (list (with-temp-buffer
          (insert-file-contents-literally file)
          (buffer-string))
        (file-attribute-modification-time (file-attributes file))))

(defun sns-roam-test--element-texts (result)
  "Return the trimmed org text of each element in RESULT's :elements."
  (mapcar #'org-ml-to-trimmed-string (plist-get result :elements)))

(ert-deftest sns-roam-body-elements-returns-the-paragraphs-before-the-first-headline ()
  ;; S11.1.  On 2026-11-09 the only way to get a note's paragraphs was to
  ;; read its file and split on blank lines (issue #7).
  (sns-roam-test--with-roam-dir
    (let ((file (expand-file-name "reference.org" org-roam-directory)))
      (sns-roam-test--register
       file
       (concat ":PROPERTIES:\n:ID: reference-id\n:KIND: reference\n:END:\n"
               "#+title: Nobl9 contract\n#+filetags: :vendor:\n\n"
               "Current edition is Enterprise.\n\n"
               "Annual price is fixed for the term.\n\n"
               "Notice window is 60 days.\n\n"
               "* History\n2026-10-24: three terms offered.\n"))
      (unwind-protect
          (let* ((state-before (sns-roam-test--file-state file))
                 (result (sns-roam-body-elements "reference-id")))
            (should (equal "reference-id" (plist-get result :id)))
            (should (equal file (plist-get result :file)))
            (should (equal '("Current edition is Enterprise."
                             "Annual price is fixed for the term."
                             "Notice window is 60 days.")
                           (sns-roam-test--element-texts result)))
            (should (equal state-before (sns-roam-test--file-state file))))
        (sns-roam-test--kill-file-buffer file)))))

(ert-deftest sns-roam-body-elements-shows-unsaved-edits ()
  ;; S11.2.  The edit that follows acts on the buffer, so the text shown
  ;; as the before text must come from the buffer too.
  (sns-roam-test--with-roam-dir
    (let ((file (expand-file-name "priced.org" org-roam-directory)))
      (let ((coding-system-for-write 'utf-8))
        (sns-roam-test--register
         file
         (concat ":PROPERTIES:\n:ID: priced-id\n:END:\n#+title: Priced\n\n"
                 "The unit price is £100.\n\nThe term is one year.\n")))
      (let ((buffer (find-file-noselect file)))
        (unwind-protect
            (progn
              (with-current-buffer buffer
                (goto-char (point-min))
                (search-forward "£100")
                (replace-match "£120" t t))
              (let* ((state-before (sns-roam-test--file-state file))
                     (result (sns-roam-body-elements "priced-id")))
                (should (equal '("The unit price is £120."
                                 "The term is one year.")
                               (sns-roam-test--element-texts result)))
                (should (equal state-before (sns-roam-test--file-state file)))
                (with-current-buffer buffer
                  (should (buffer-modified-p))
                  (should (string-match-p "£120" (buffer-string))))))
          ;; Clear the flag so killing the buffer does not ask to save it.
          (with-current-buffer buffer
            (set-buffer-modified-p nil))
          (kill-buffer buffer))))))

(ert-deftest sns-roam-body-elements-returns-nil-for-a-note-with-no-body ()
  ;; S11.3
  (sns-roam-test--with-roam-dir
    (let ((file (expand-file-name "bare.org" org-roam-directory)))
      (sns-roam-test--register
       file ":PROPERTIES:\n:ID: bare-id\n:END:\n#+title: Bare\n")
      (unwind-protect
          (let ((result (sns-roam-body-elements "bare-id")))
            (should (equal "bare-id" (plist-get result :id)))
            (should (equal file (plist-get result :file)))
            (should (null (plist-get result :elements))))
        (sns-roam-test--kill-file-buffer file)))))

(ert-deftest sns-roam-body-elements-reads-back-what-create-node-wrote ()
  (sns-roam-test--with-roam-dir
    (let* ((body (sns-roam--parse-body-elements
                  "A claim stated plainly.\n\n- first ground\n- second ground\n"))
           (created (sns-roam-create-node "Probe" "permanent" body))
           (file (plist-get created :file)))
      (unwind-protect
          (should (equal '("A claim stated plainly."
                           "- first ground\n- second ground")
                         (sns-roam-test--element-texts
                          (sns-roam-body-elements (plist-get created :id)))))
        (sns-roam-test--kill-file-buffer file)))))

(ert-deftest sns-roam-body-elements-rejects-an-unknown-id ()
  (sns-roam-test--with-roam-dir
    (sns-roam-test--should-have
     (sns-roam-test--error-data 'sns-roam-unknown-id
                                (lambda () (sns-roam-body-elements "missing-id")))
     :id "missing-id")))

(ert-deftest sns-roam-expand-rejects-an-unknown-id ()
  (sns-roam-test--with-roam-dir
    (sns-roam-test--should-have
     (sns-roam-test--error-data 'sns-roam-unknown-id
                                (lambda () (sns-roam-expand "missing-id")))
     :id "missing-id")))

;;; --- a note whose file has moved (slice 20) ---

(defmacro sns-roam-test--with-moved-note (&rest body)
  "Run BODY with a created note's file renamed after it was indexed.
Binds `id' to the note's ID, `old-file' to the path the database
still holds and `new-file' to where the file now is.  The database is
not synced after the rename, as when the user moves a note outside
Emacs.  Kills any buffer on either path afterwards."
  (declare (indent 0))
  `(sns-roam-test--with-roam-dir
     (let* ((created (sns-roam-create-node
                      "Tide tables" "permanent"
                      (sns-roam--parse-body-elements "High water is at noon.\n")))
            (id (plist-get created :id))
            (old-file (plist-get created :file))
            (new-file (expand-file-name "moved-tide-tables.org"
                                        org-roam-directory)))
       (sns-roam-test--kill-file-buffer old-file)
       (rename-file old-file new-file)
       (unwind-protect (progn ,@body)
         (sns-roam-test--kill-file-buffer old-file)
         (sns-roam-test--kill-file-buffer new-file)))))

(defun sns-roam-test--should-report-missing-file (id old-file thunk)
  "Show that calling THUNK raises the missing-file error for ID's OLD-FILE.
Also shows the call opened no buffer on OLD-FILE and left no file
there."
  (sns-roam-test--should-have
   (sns-roam-test--error-data 'sns-roam-missing-file thunk)
   :id id :path old-file)
  (should-not (get-file-buffer old-file))
  (should-not (file-exists-p old-file)))

(ert-deftest sns-roam-body-elements-reports-a-moved-file ()
  ;; S20.1.  On 2026-11-11 this returned `:elements nil' for a renamed
  ;; note, as if it were empty (issue #13).
  (sns-roam-test--with-moved-note
    (sns-roam-test--should-report-missing-file
     id old-file (lambda () (sns-roam-body-elements id)))))

(ert-deftest sns-roam-expand-reports-a-moved-file ()
  ;; S20.1
  (sns-roam-test--with-moved-note
    (sns-roam-test--should-report-missing-file
     id old-file (lambda () (sns-roam-expand id)))))

(ert-deftest sns-roam-set-body-reports-a-moved-file ()
  ;; S20.2.  On 2026-11-11 this raised "has no top-level section", which
  ;; names a malformed file (issue #13).
  (sns-roam-test--with-moved-note
    (sns-roam-test--should-report-missing-file
     id old-file (lambda () (sns-roam-set-body id "Low water is at six.")))
    (should (string-match-p "^High water is at noon\\.$"
                            (sns-roam-test--file-text new-file)))))

(ert-deftest sns-roam-set-property-reports-a-moved-file ()
  ;; S20.2
  (sns-roam-test--with-moved-note
    (sns-roam-test--should-report-missing-file
     id old-file (lambda () (sns-roam-set-property id "KIND" "reference")))))

(ert-deftest sns-roam-moved-file-leaves-an-open-buffer-alone ()
  ;; S20.2.  A buffer the user already has on the old path may hold
  ;; unsaved edits, so the error must not touch it.
  (sns-roam-test--with-roam-dir
    (let* ((created (sns-roam-create-node
                     "Tide tables" "permanent"
                     (sns-roam--parse-body-elements "High water is at noon.\n")))
           (id (plist-get created :id))
           (old-file (plist-get created :file))
           (new-file (expand-file-name "moved-tide-tables.org"
                                       org-roam-directory))
           (buffer (find-file-noselect old-file)))
      (unwind-protect
          (progn
            (with-current-buffer buffer
              (goto-char (point-min))
              (search-forward "noon")
              (replace-match "one" t t))
            (rename-file old-file new-file)
            (sns-roam-test--should-have
             (sns-roam-test--error-data
              'sns-roam-missing-file
              (lambda () (sns-roam-set-body id "Low water is at six.")))
             :id id :path old-file)
            (should (eq buffer (get-file-buffer old-file)))
            (with-current-buffer buffer
              (should (buffer-modified-p))
              (should (string-match-p "^High water is at one\\.$"
                                      (buffer-string))))
            (should-not (file-exists-p old-file)))
        ;; Clear the flag so killing the buffer does not ask to save it.
        (with-current-buffer buffer
          (set-buffer-modified-p nil))
        (kill-buffer buffer)
        (sns-roam-test--kill-file-buffer new-file)))))

;;; --- sns-roam-insert-element (slice 12) ---

(defconst sns-roam-test--reference-header
  ":PROPERTIES:\n:ID: contract-id\n:KIND: reference\n:END:\n#+title: Vendor contract\n\n"
  "Drawer and title of the reference note the slice 12 tests edit.")

(defun sns-roam-test--containing (text)
  "Return a predicate true of an org-ml node whose text contains TEXT."
  (lambda (node)
    (string-match-p (regexp-quote text) (org-ml-to-trimmed-string node))))

(defmacro sns-roam-test--with-reference-note (body-text &rest body)
  "Run BODY with `file' bound to a registered reference note.
The note is `sns-roam-test--reference-header' followed by BODY-TEXT,
with ID \"contract-id\".  Kills the note's buffer afterwards."
  (declare (indent 1))
  `(sns-roam-test--with-roam-dir
     (let ((file (expand-file-name "contract.org" org-roam-directory)))
       (sns-roam-test--register
        file (concat sns-roam-test--reference-header ,body-text))
       (unwind-protect (progn ,@body)
         (sns-roam-test--kill-file-buffer file)))))

(ert-deftest sns-roam-insert-element-adds-a-history-line-above-the-newest ()
  ;; S12.1.  On 2026-11-10 a rewrite of one paragraph with `set-body'
  ;; dropped a line (issue #10).
  (sns-roam-test--with-reference-note
      "Edition: Pro.\n\nOpen: renewal date.\n\n2026-10-24: offered terms.\n"
    (let ((result (sns-roam-insert-element
                   "contract-id"
                   (sns-roam-test--containing "2026-10-24")
                   (org-ml-build-paragraph "2026-11-11: signed a 2-year term."))))
      (sns-roam-test--should-have result :id "contract-id" :file file)
      (should (equal (concat ":END:\n#+title: Vendor contract\n\n"
                             "Edition: Pro.\n\nOpen: renewal date.\n\n"
                             "2026-11-11: signed a 2-year term.\n\n"
                             "2026-10-24: offered terms.\n")
                     (sns-roam-test--text-from-drawer-end file))))))

(ert-deftest sns-roam-insert-element-after-the-last-paragraph-ends-the-note ()
  ;; S12.2
  (sns-roam-test--with-reference-note
      "Edition: Pro.\n\nOpen: renewal date.\n\n2026-10-24: offered terms.\n"
    (sns-roam-insert-element "contract-id"
                             (sns-roam-test--containing "2026-10-24")
                             (org-ml-build-paragraph "See also the vendor list.")
                             t)
    (should (equal (concat ":END:\n#+title: Vendor contract\n\n"
                           "Edition: Pro.\n\nOpen: renewal date.\n\n"
                           "2026-10-24: offered terms.\n\n"
                           "See also the vendor list.\n")
                   (sns-roam-test--text-from-drawer-end file)))))

(ert-deftest sns-roam-insert-element-refuses-an-anchor-that-matches-two ()
  ;; S12.3
  (sns-roam-test--with-reference-note
      "2026-10-24: offered terms.\n\n2026-10-30: asked for a discount.\n"
    (let ((state-before (sns-roam-test--file-state file)))
      (sns-roam-test--should-have
       (sns-roam-test--error-data
        'sns-roam-match-count
        (lambda ()
          (sns-roam-insert-element "contract-id"
                                   (sns-roam-test--containing "2026")
                                   (org-ml-build-paragraph "New line.")
                                   t)))
       :id "contract-id" :file file
       :operation 'sns-roam-insert-element :count 2)
      (should (equal state-before (sns-roam-test--file-state file))))))

(ert-deftest sns-roam-insert-element-refuses-an-anchor-that-matches-nothing ()
  (sns-roam-test--with-reference-note
      "Edition: Pro.\n\nOpen: renewal date.\n"
    (let ((state-before (sns-roam-test--file-state file)))
      (sns-roam-test--should-have
       (sns-roam-test--error-data
        'sns-roam-match-count
        (lambda ()
          (sns-roam-insert-element "contract-id"
                                   (sns-roam-test--containing "2027")
                                   (org-ml-build-paragraph "New line."))))
       :operation 'sns-roam-insert-element :count 0)
      (should (equal state-before (sns-roam-test--file-state file))))))

(ert-deftest sns-roam-insert-element-never-shows-the-header-to-the-predicate ()
  ;; The title and the drawer both contain "contract", so a predicate
  ;; that saw them would match three elements.
  (sns-roam-test--with-reference-note
      "The contract runs two years.\n"
    (sns-roam-insert-element "contract-id"
                             (sns-roam-test--containing "ontract")
                             (org-ml-build-paragraph "Notice is 60 days.")
                             t)
    (should (equal (concat ":END:\n#+title: Vendor contract\n\n"
                           "The contract runs two years.\n\n"
                           "Notice is 60 days.\n")
                   (sns-roam-test--text-from-drawer-end file)))))

(ert-deftest sns-roam-insert-element-before-the-first-body-element ()
  (sns-roam-test--with-reference-note
      "Edition: Pro.\n\nOpen: renewal date.\n"
    (sns-roam-insert-element "contract-id"
                             (sns-roam-test--containing "Edition")
                             (org-ml-build-paragraph "Vendor: Atalanta Systems."))
    (should (equal (concat ":END:\n#+title: Vendor contract\n\n"
                           "Vendor: Atalanta Systems.\n\nEdition: Pro.\n\n"
                           "Open: renewal date.\n")
                   (sns-roam-test--text-from-drawer-end file)))))

(ert-deftest sns-roam-insert-element-keeps-extra-space-after-the-anchor ()
  ;; No gap shrinks: the anchor keeps its two blank lines, and the new
  ;; paragraph has one before the body element that follows it.
  (sns-roam-test--with-reference-note
      "Edition: Pro.\n\n\nOpen: renewal date.\n"
    (sns-roam-insert-element "contract-id"
                             (sns-roam-test--containing "Edition")
                             (org-ml-build-paragraph "Units: 40.")
                             t)
    (should (equal (concat ":END:\n#+title: Vendor contract\n\n"
                           "Edition: Pro.\n\n\nUnits: 40.\n\n"
                           "Open: renewal date.\n")
                   (sns-roam-test--text-from-drawer-end file)))))

(ert-deftest sns-roam-insert-element-after-a-footnote-keeps-the-three-apart ()
  ;; Org ends a footnote definition only at two blank lines, so a
  ;; shrunk gap would pull the new paragraph into the footnote.
  (sns-roam-test--with-reference-note
      (concat "Prices follow the list.[fn:1]\n\n"
              "[fn:1] List price as of 2026.\n\n\n"
              "Prices are per seat.\n")
    (sns-roam-insert-element "contract-id"
                             (lambda (node)
                               (org-ml-is-type 'footnote-definition node))
                             (org-ml-build-paragraph "Counts are at renewal.")
                             t)
    (let ((elements (plist-get (sns-roam-body-elements "contract-id")
                               :elements)))
      (should (equal '(paragraph footnote-definition paragraph paragraph)
                     (mapcar #'org-ml-get-type elements)))
      (should (equal '("Counts are at renewal." "Prices are per seat.")
                     (mapcar #'org-ml-to-trimmed-string (cddr elements)))))))

(ert-deftest sns-roam-insert-element-refuses-a-plain-list ()
  ;; A list beside a list would merge into one, so only paragraphs go in.
  (sns-roam-test--with-reference-note
      "Edition: Pro.\n\nOpen: renewal date.\n"
    (let ((state-before (sns-roam-test--file-state file)))
      (sns-roam-test--should-have
       (sns-roam-test--error-data
        'sns-roam-unsupported-element
        (lambda ()
          (sns-roam-insert-element
           "contract-id"
           (sns-roam-test--containing "Edition")
           (car (sns-roam--parse-body-elements "- seats\n- users\n"))
           t)))
       :id "contract-id" :operation 'sns-roam-insert-element :type 'plain-list)
      (should (equal state-before (sns-roam-test--file-state file))))))

(ert-deftest sns-roam-insert-element-refuses-a-plan-that-would-not-reparse ()
  ;; A spacing helper that leaves no blank lines makes the new paragraph
  ;; and its neighbours read back as one, which the check must catch.
  (sns-roam-test--with-reference-note
      "Edition: Pro.\n\nOpen: renewal date.\n"
    (let ((state-before (sns-roam-test--file-state file))
          (data (cl-letf (((symbol-function 'sns-roam--insert-beside)
                          (lambda (children anchor new-element _after)
                            (cl-mapcan
                             (lambda (child)
                               (let ((flat (org-ml-set-property
                                            :post-blank 0 child)))
                                 (if (eq child anchor)
                                     (list flat (org-ml-set-property
                                                 :post-blank 0 new-element))
                                   (list flat))))
                             children))))
                 (sns-roam-test--error-data
                  'sns-roam-reparse-mismatch
                  (lambda ()
                    (sns-roam-insert-element "contract-id"
                                             (sns-roam-test--containing "Edition")
                                             (org-ml-build-paragraph "Units: 40.")
                                             t))))))
      (sns-roam-test--should-have
       data
       :id "contract-id" :file file :operation 'sns-roam-insert-element
       :planned '((paragraph "Edition: Pro.")
                  (paragraph "Units: 40.")
                  (paragraph "Open: renewal date."))
       :actual '((paragraph "Edition: Pro.\nUnits: 40.\nOpen: renewal date.")))
      (should (equal state-before (sns-roam-test--file-state file))))))

(ert-deftest sns-roam-insert-into-section-is-callable-without-a-file ()
  ;; The calculation from section to section needs no database or file.
  (let* ((section (car (org-ml-get-children
                        (with-temp-buffer
                          (insert sns-roam-test--reference-header
                                  "Edition: Pro.\n\nOpen: renewal date.\n")
                          (org-ml-parse-this-buffer)))))
         (result (sns-roam--insert-into-section
                  section
                  (sns-roam-test--containing "Open")
                  (org-ml-build-paragraph "Units: 40.")
                  nil)))
    (should (equal '("Edition: Pro." "Units: 40." "Open: renewal date.")
                   (mapcar #'org-ml-to-trimmed-string
                           (seq-remove #'sns-roam--section-header-p
                                       (org-ml-get-children result)))))
    (sns-roam-test--should-have
     (sns-roam-test--error-data
      'sns-roam-match-count
      (lambda ()
        (sns-roam--insert-into-section section
                                       (sns-roam-test--containing ".")
                                       (org-ml-build-paragraph "Units: 40.")
                                       nil)))
     :operation 'sns-roam-insert-element :count 2)))

(ert-deftest sns-roam-insert-element-adds-no-blank-line-before-a-headline ()
  (sns-roam-test--with-reference-note
      "Edition: Pro.\n* History\n2026-10-24: offered terms.\n"
    (sns-roam-insert-element "contract-id"
                             (sns-roam-test--containing "Edition")
                             (org-ml-build-paragraph "Units: 40.")
                             t)
    (should (equal (concat ":END:\n#+title: Vendor contract\n\n"
                           "Edition: Pro.\n\nUnits: 40.\n"
                           "* History\n2026-10-24: offered terms.\n")
                   (sns-roam-test--text-from-drawer-end file)))))

(defconst sns-roam-test--table-between-prose
  "Seats by year:\n| 2025 | 40 |\n| 2026 | 55 |\nPrices are per seat.\n"
  "A body whose table has prose on both sides with no blank line between.")

(ert-deftest sns-roam-insert-element-after-a-table-keeps-the-prose-apart ()
  ;; Org joins a paragraph to the prose that follows it with no blank
  ;; line, so the new paragraph must not inherit the table's zero.
  (sns-roam-test--with-reference-note
      sns-roam-test--table-between-prose
    (sns-roam-insert-element "contract-id"
                             (lambda (node) (org-ml-is-type 'table node))
                             (org-ml-build-paragraph "Counts are at renewal.")
                             t)
    (should (equal '("Seats by year:"
                     "| 2025 | 40 |\n| 2026 | 55 |"
                     "Counts are at renewal."
                     "Prices are per seat.")
                   (sns-roam-test--element-texts
                    (sns-roam-body-elements "contract-id"))))))

(ert-deftest sns-roam-insert-element-before-a-table-keeps-the-prose-apart ()
  ;; The paragraph before the anchor is the new element's other neighbour.
  (sns-roam-test--with-reference-note
      sns-roam-test--table-between-prose
    (sns-roam-insert-element "contract-id"
                             (lambda (node) (org-ml-is-type 'table node))
                             (org-ml-build-paragraph "Counts are at renewal."))
    (should (equal '("Seats by year:"
                     "Counts are at renewal."
                     "| 2025 | 40 |\n| 2026 | 55 |"
                     "Prices are per seat.")
                   (sns-roam-test--element-texts
                    (sns-roam-body-elements "contract-id"))))))

;;; --- sns-roam-history-anchor (slice 13) ---

(defconst sns-roam-test--history-body
  (concat "Current state: Pro edition, 40 seats.\n\n"
          "Open: renewal date.\n\n"
          "2026-11-09: asked for a discount (email from the vendor).\n\n"
          "2026-11-06: offered 1- and 2-year terms (call).\n")
  "Body of a reference note in the layout `sns-roam-history-anchor' reads.")

(defun sns-roam-test--anchor (body-text date)
  "Return :anchor and :after from `sns-roam-history-anchor' on BODY-TEXT for DATE."
  (sns-roam-test--with-reference-note body-text
    (let ((result (sns-roam-history-anchor "contract-id" date)))
      (list (plist-get result :anchor) (plist-get result :after)))))

(defun sns-roam-test--anchor-error (kind body-text date)
  "Return the data of condition KIND `sns-roam-history-anchor' raises on BODY-TEXT for DATE.
Also shows the data names the note and its file."
  (sns-roam-test--with-reference-note body-text
    (let ((data (sns-roam-test--error-data
                 kind
                 (lambda () (sns-roam-history-anchor "contract-id" date)))))
      (sns-roam-test--should-have data :id "contract-id" :file file)
      data)))

(ert-deftest sns-roam-history-anchor-puts-a-middle-date-before-the-older-line ()
  ;; S13.1
  (sns-roam-test--with-reference-note sns-roam-test--history-body
    (should (equal (list :id "contract-id" :file file
                         :anchor "2026-11-06: offered 1- and 2-year terms (call)."
                         :after nil)
                   (sns-roam-history-anchor "contract-id" "2026-11-08")))))

(ert-deftest sns-roam-history-anchor-puts-the-newest-date-before-the-newest-line ()
  (should (equal '("2026-11-09: asked for a discount (email from the vendor)." nil)
                 (sns-roam-test--anchor sns-roam-test--history-body "2026-11-12"))))

(ert-deftest sns-roam-history-anchor-puts-the-oldest-date-after-the-last-line ()
  (should (equal '("2026-11-06: offered 1- and 2-year terms (call)." t)
                 (sns-roam-test--anchor sns-roam-test--history-body "2026-10-01"))))

(ert-deftest sns-roam-history-anchor-puts-an-equal-date-before-the-existing-line ()
  (should (equal '("2026-11-06: offered 1- and 2-year terms (call)." nil)
                 (sns-roam-test--anchor sns-roam-test--history-body "2026-11-06"))))

(ert-deftest sns-roam-history-anchor-with-no-history-goes-after-the-last-paragraph ()
  (should (equal '("Open: renewal date." t)
                 (sns-roam-test--anchor
                  "Current state: Pro edition.\n\nOpen: renewal date.\n"
                  "2026-11-08"))))

(ert-deftest sns-roam-history-anchor-writes-nothing ()
  (sns-roam-test--with-reference-note sns-roam-test--history-body
    (let ((state-before (sns-roam-test--file-state file)))
      (sns-roam-history-anchor "contract-id" "2026-11-08")
      (should (equal state-before (sns-roam-test--file-state file)))
      (should-not (buffer-modified-p (get-file-buffer file))))))

(ert-deftest sns-roam-history-anchor-refuses-a-date-not-written-yyyy-mm-dd ()
  (sns-roam-test--should-have
   (sns-roam-test--anchor-error 'sns-roam-bad-date sns-roam-test--history-body
                                "8 Nov 2026")
   :date "8 Nov 2026"))

(ert-deftest sns-roam-history-anchor-refuses-a-note-with-a-heading ()
  ;; S13.2: the heading follows the body, so only a parse of the whole
  ;; buffer sees it.
  (sns-roam-test--should-have
   (sns-roam-test--anchor-error
    'sns-roam-unsupported-element
    (concat "Current state: Pro edition.\n\n"
            "* History\n2026-11-06: offered terms.\n")
    "2026-11-12")
   :operation 'sns-roam-history-anchor :type 'headline :title "History"))

(ert-deftest sns-roam-history-anchor-refuses-a-list ()
  (sns-roam-test--should-have
   (sns-roam-test--anchor-error
    'sns-roam-unsupported-element
    "Current state: Pro edition.\n\n- 2026-11-06: offered terms.\n"
    "2026-11-08")
   :operation 'sns-roam-history-anchor :type 'plain-list))

(ert-deftest sns-roam-history-anchor-refuses-an-empty-body ()
  (sns-roam-test--should-have
   (sns-roam-test--anchor-error 'sns-roam-history-layout "" "2026-11-08")
   :reason 'no-paragraphs))

(ert-deftest sns-roam-history-anchor-refuses-an-open-paragraph-after-a-dated-line ()
  (sns-roam-test--should-have
   (sns-roam-test--anchor-error
    'sns-roam-history-layout
    (concat "Current state: Pro edition.\n\n"
            "2026-11-09: asked for a discount.\n\n"
            "Open: renewal date.\n\n"
            "2026-11-06: offered terms.\n")
    "2026-11-08")
   :reason 'not-one-run))

(ert-deftest sns-roam-history-anchor-refuses-dated-lines-oldest-first ()
  (sns-roam-test--should-have
   (sns-roam-test--anchor-error
    'sns-roam-history-layout
    (concat "Open: renewal date.\n\n"
            "2026-11-06: offered terms.\n\n"
            "2026-11-09: asked for a discount.\n")
    "2026-11-08")
   :reason 'not-newest-first :dates '("2026-11-06" "2026-11-09")))

(ert-deftest sns-roam-history-anchor-refuses-an-anchor-text-that-appears-twice ()
  (sns-roam-test--should-have
   (sns-roam-test--anchor-error
    'sns-roam-match-count
    (concat "Open: renewal date.\n\n"
            "2026-11-06: offered terms.\n\n"
            "2026-11-06: offered terms.\n")
    "2026-11-08")
   :operation 'sns-roam-history-anchor :count 2
   :anchor "2026-11-06: offered terms."))

(ert-deftest sns-roam-history-anchor-reports-a-duplicated-newest-line ()
  ;; S21.2: the second note of a batch has its newest line twice, so a
  ;; line dated after it has two places to go.
  (sns-roam-test--should-have
   (sns-roam-test--anchor-error
    'sns-roam-match-count
    (concat "Current state: Pro edition.\n\n"
            "2026-11-11: weekly check-in.\n\n"
            "2026-11-11: weekly check-in.\n")
    "2026-11-12")
   :operation 'sns-roam-history-anchor :count 2
   :anchor "2026-11-11: weekly check-in."))

(ert-deftest sns-roam-history-anchor-rejects-an-unknown-id ()
  (sns-roam-test--with-roam-dir
    (sns-roam-test--should-have
     (sns-roam-test--error-data
      'sns-roam-unknown-id
      (lambda () (sns-roam-history-anchor "missing-id" "2026-11-08")))
     :id "missing-id")))

(ert-deftest sns-roam-history-anchor-feeds-insert-element ()
  ;; S13.3: the anchor and :after go to `insert-element' unchanged, and
  ;; every other paragraph, the link included, keeps its text.
  (sns-roam-test--with-reference-note
      (concat "Current state: Pro edition.\n\n"
              "Open: renewal date.\n\n"
              "Related claims: [[id:claim-id][Seats track headcount]].\n\n"
              "2026-11-09: asked for a discount.\n\n"
              "2026-11-06: offered terms.\n")
    (let* ((place (sns-roam-history-anchor "contract-id" "2026-11-08"))
           (anchor (plist-get place :anchor)))
      (sns-roam-insert-element "contract-id"
                               (lambda (node)
                                 (string= anchor (org-ml-to-trimmed-string node)))
                               (org-ml-build-paragraph "2026-11-08: met the vendor.")
                               (plist-get place :after))
      (should (equal (concat ":END:\n#+title: Vendor contract\n\n"
                             "Current state: Pro edition.\n\n"
                             "Open: renewal date.\n\n"
                             "Related claims: [[id:claim-id][Seats track headcount]].\n\n"
                             "2026-11-09: asked for a discount.\n\n"
                             "2026-11-08: met the vendor.\n\n"
                             "2026-11-06: offered terms.\n")
                     (sns-roam-test--text-from-drawer-end file))))))

;;; --- an edit writes only what it changed (slice 14) ---

(defconst sns-roam-test--typed-note
  (concat ":PROPERTIES:\n:ID: typed-id\n:KIND: fleeting\n:END:\n"
          "#+title: Typed note\n\n"
          "Intro.\n\n"
          "|a|b|\n\n"
          "+  item one\n\n"
          "#+BEGIN_SRC sh\necho hi\n#+END_SRC\n\n"
          "* Notes\n|c|d|\n")
  "A note whose table, list and source block are not in org's printed form.
Org prints them as `| a | b |', `- item one' and a lowercase
`#+begin_src', so a write of any of them shows in the file.")

(defconst sns-roam-test--typed-file-name "20261111090000-typed_note.org"
  "File name of the typed note, in the roam form `sns-roam-rename' needs.")

(defun sns-roam-test--changed-lines (before after)
  "Return the lines a diff of BEFORE and AFTER shows, as (:removed R :added A).
Lines the two texts share at the start, and then at the end of what
is left, are dropped; R and A are the lines between."
  (let ((old-lines (split-string before "\n"))
        (new-lines (split-string after "\n")))
    (while (and old-lines new-lines (equal (car old-lines) (car new-lines)))
      (setq old-lines (cdr old-lines)
            new-lines (cdr new-lines)))
    (let ((old-reversed (reverse old-lines))
          (new-reversed (reverse new-lines)))
      (while (and old-reversed new-reversed
                  (equal (car old-reversed) (car new-reversed)))
        (setq old-reversed (cdr old-reversed)
              new-reversed (cdr new-reversed)))
      (list :removed (reverse old-reversed)
            :added (reverse new-reversed)))))

(defmacro sns-roam-test--with-typed-note (&rest body)
  "Run BODY with `file' and `before' bound for a registered typed note.
The note is `sns-roam-test--typed-note' with ID \"typed-id\", and
`before' is its text.  A second note, \"other-id\", is there to link
to.  Kills every note buffer afterwards, under its old or new name."
  (declare (indent 0))
  `(sns-roam-test--with-roam-dir
     (let ((file (expand-file-name sns-roam-test--typed-file-name
                                   org-roam-directory)))
       (sns-roam-test--register file sns-roam-test--typed-note)
       (sns-roam-test--register
        (expand-file-name "other.org" org-roam-directory)
        ":PROPERTIES:\n:ID: other-id\n:END:\n#+title: Other\n")
       (let ((before (sns-roam-test--file-text file)))
         (unwind-protect (progn ,@body)
           (mapc #'sns-roam-test--kill-file-buffer
                 (directory-files org-roam-directory t "\\.org\\'")))))))

(ert-deftest sns-roam-replace-element-leaves-a-typed-table-and-list-alone ()
  ;; S14.1.  On 2026-11-11 this edit also rewrote `|a|b|' as `| a | b |'
  ;; and `+  item one' as `- item one' (issue #14).
  (sns-roam-test--with-typed-note
    (sns-roam-replace-element
     "typed-id"
     (lambda (node) (equal "Intro." (org-ml-to-trimmed-string node)))
     (org-ml-build-paragraph :post-blank 1 "New intro."))
    (should (equal '(:removed ("Intro.") :added ("New intro."))
                   (sns-roam-test--changed-lines
                    before (sns-roam-test--file-text file))))))

(ert-deftest sns-roam-append-link-leaves-the-rest-alone ()
  ;; S14.2.  The new paragraph and its blank line go after the source
  ;; block's blank line, straight before `* Notes'.
  (sns-roam-test--with-typed-note
    (sns-roam-append-link "typed-id" "other-id" "Other" "See " ".")
    (should (equal '(:removed () :added ("See [[id:other-id][Other]]." ""))
                   (sns-roam-test--changed-lines
                    before (sns-roam-test--file-text file))))))

(ert-deftest sns-roam-rename-changes-only-the-title-line ()
  ;; S14.3.  The owner's Emacs runs the autosync mode, which records the
  ;; new title on save; the slug of the new name is made from it.
  (sns-roam-test--with-typed-note
    (org-roam-db-autosync-mode 1)
    (unwind-protect
        (let ((renamed (plist-get (sns-roam-rename "typed-id" "Renamed note")
                                  :file)))
          (should (equal "20261111090000-renamed_note.org"
                         (file-name-nondirectory renamed)))
          (should-not (file-exists-p file))
          (should (equal '(:removed ("#+title: Typed note")
                           :added ("#+title: Renamed note"))
                         (sns-roam-test--changed-lines
                          before (sns-roam-test--file-text renamed)))))
      (org-roam-db-autosync-mode -1))))

(ert-deftest sns-roam-set-body-leaves-the-header-and-headings-alone ()
  ;; `set-body' replaces every body element, so those lines go; the
  ;; drawer, the title and the typed table under `* Notes' stay.
  (sns-roam-test--with-typed-note
    (sns-roam-set-body "typed-id" "New intro.\n\n")
    (should (equal '(:removed ("Intro." "" "|a|b|" "" "+  item one" ""
                               "#+BEGIN_SRC sh" "echo hi" "#+END_SRC")
                     :added ("New intro."))
                   (sns-roam-test--changed-lines
                    before (sns-roam-test--file-text file))))))

(ert-deftest sns-roam-insert-element-leaves-typed-elements-alone ()
  (sns-roam-test--with-typed-note
    (sns-roam-insert-element "typed-id"
                             (sns-roam-test--containing "Intro.")
                             (org-ml-build-paragraph "Added.")
                             t)
    (should (equal '(:removed () :added ("Added." ""))
                   (sns-roam-test--changed-lines
                    before (sns-roam-test--file-text file))))))

(ert-deftest sns-roam-set-property-writes-only-the-drawer ()
  ;; The drawer is the element the edit changes, so org may print it in
  ;; its own form; every line after it keeps its text.
  (sns-roam-test--with-typed-note
    (should (sns-roam-set-property "typed-id" "KIND" "permanent"))
    (let ((after (sns-roam-test--file-text file)))
      (should (string-match-p "^:KIND: +permanent$" after))
      (should (string-match-p "^:ID: +typed-id$" after))
      (should (equal (substring before (string-match "^:END:$" before))
                     (substring after (string-match "^:END:$" after)))))))

(ert-deftest sns-roam-set-property-with-the-same-value-writes-nothing ()
  ;; Setting a property to the value it has leaves every byte alone.
  (sns-roam-test--with-typed-note
    (sns-roam-set-property "typed-id" "KIND" "fleeting")
    (should (equal before (sns-roam-test--file-text file)))))

(ert-deftest sns-roam-diff-shows-unsaved-edits-the-save-writes ()
  ;; The owner has changed "Intro." to "Edited." in Emacs without
  ;; saving.  A same-value property change saves the buffer, so the
  ;; file changes, and the diff must say so rather than report nothing.
  (sns-roam-test--with-typed-note
    (with-current-buffer (find-file-noselect file)
      (goto-char (point-min))
      (search-forward "Intro.")
      (replace-match "Edited."))
    (let ((diff (plist-get (sns-roam-set-property "typed-id" "KIND" "fleeting")
                           :diff)))
      (should (string-match-p "^-Intro\\.$" diff))
      (should (string-match-p "^\\+Edited\\.$" diff)))))

(ert-deftest sns-roam-section-edits-keep-unchanged-children-unwritten ()
  ;; The calculation needs no file: replacing one paragraph through a
  ;; transform, which copies the other children, gives one edit over
  ;; that paragraph's own bounds.
  (with-temp-buffer
    (insert sns-roam-test--typed-note)
    (let* ((section (car (org-ml-get-children (org-ml-parse-this-buffer))))
           (intro-p (lambda (node)
                      (equal "Intro." (org-ml-to-trimmed-string node))))
           (intro (seq-find intro-p (org-ml-get-children section)))
           (new-section (org-ml-match-map
                         `((:pred ,intro-p))
                         (lambda (_old)
                           (org-ml-build-paragraph :post-blank 1 "New intro."))
                         section)))
      (should (equal (list (list :begin (org-ml-get-property :begin intro)
                                 :end (org-ml-get-property :end intro)
                                 :text "New intro.\n\n"))
                     (sns-roam--section-edits
                      (org-ml-get-children section)
                      (org-ml-get-children new-section)))))))

(ert-deftest sns-roam-tests-use-a-temporary-database ()
  ;; The test file sets the location before it loads org-roam, so the
  ;; owner's database is never the value, setup included.
  (should (equal sns-roam-test--db-location org-roam-db-location))
  (should (string-prefix-p (file-truename temporary-file-directory)
                           (file-truename org-roam-db-location)))
  (should-not (equal (file-truename org-roam-db-location)
                     (file-truename
                      (eval (car (get 'org-roam-db-location 'standard-value)))))))

;;; --- a change to the blank lines alone keeps the typed text (slice 19) ---

(defmacro sns-roam-test--with-bare-note (text &rest body)
  "Run BODY with `file' and `before' bound for a registered note whose text is TEXT.
The note's ID is \"bare-id\", and `before' is its text.  A note with
ID \"other-id\" is there to link to."
  (declare (indent 1))
  `(sns-roam-test--with-roam-dir
     (let ((file (expand-file-name "bare.org" org-roam-directory)))
       (sns-roam-test--register file ,text)
       (sns-roam-test--register
        (expand-file-name "other.org" org-roam-directory)
        ":PROPERTIES:\n:ID: other-id\n:END:\n#+title: Other\n")
       (let ((before (sns-roam-test--file-text file)))
         (ignore before)
         (unwind-protect (progn ,@body)
           (mapc #'sns-roam-test--kill-file-buffer
                 (directory-files org-roam-directory t "\\.org\\'")))))))

(ert-deftest sns-roam-append-link-keeps-a-typed-source-block ()
  ;; S19.1.  On 2026-11-11 the block came back as `#+begin_src sh' with
  ;; its body indented, because it gained a blank line (issue #17).
  (sns-roam-test--with-bare-note
      ":PROPERTIES:\n:ID: bare-id\n:END:\n#+title: Bare\n#+BEGIN_SRC sh\necho hi\n#+END_SRC\n"
    (sns-roam-append-link "bare-id" "other-id" "Other" "See " ".")
    (should (equal '(:removed () :added ("See [[id:other-id][Other]]." ""))
                   (sns-roam-test--changed-lines
                    before (sns-roam-test--file-text file))))
    (should (equal (concat before "\nSee [[id:other-id][Other]].\n")
                   (sns-roam-test--file-text file)))))

(ert-deftest sns-roam-insert-element-after-a-typed-table ()
  ;; S19.2.  The table gains a blank line and keeps `|a|b|'.
  (sns-roam-test--with-bare-note
      ":PROPERTIES:\n:ID: bare-id\n:END:\n#+title: Bare\nIntro.\n\n|a|b|\nOutro.\n"
    (sns-roam-insert-element "bare-id"
                             (sns-roam-test--containing "| a | b |")
                             (org-ml-build-paragraph "New.")
                             t)
    (should (equal '(:removed () :added ("" "New." ""))
                   (sns-roam-test--changed-lines
                    before (sns-roam-test--file-text file))))
    (should (equal ":PROPERTIES:\n:ID: bare-id\n:END:\n#+title: Bare\nIntro.\n\n|a|b|\n\nNew.\n\nOutro.\n"
                   (sns-roam-test--file-text file)))))

(ert-deftest sns-roam-update-section-writes-a-changed-element-in-org-form ()
  ;; Out of scope for slice 19: an element whose content changes as
  ;; well as its blank lines is still written as org prints it.
  (sns-roam-test--with-typed-note
    (sns-roam--update-section
     'sns-roam-set-body "typed-id"
     (lambda (section)
       (sns-roam--map-children
        (lambda (children)
          (mapcar (lambda (child)
                    (if (org-ml-is-type 'src-block child)
                        ;; Not `org-ml->>', which edits the parse in place.
                        (org-ml-set-property
                         :post-blank 2
                         (org-ml-set-property :value "echo bye\n" child))
                      child))
                  children))
        section)))
    (should (equal '(:removed ("#+BEGIN_SRC sh" "echo hi" "#+END_SRC")
                     :added ("#+begin_src sh" "  echo bye" "#+end_src" ""))
                   (sns-roam-test--changed-lines
                    before (sns-roam-test--file-text file))))))

(ert-deftest sns-roam-section-edits-write-only-new-blank-lines ()
  ;; A child whose only change is its :post-blank gets one edit, which
  ;; replaces the blank lines after its last non-blank character with
  ;; those `org-ml-to-string' prints for the new :post-blank.
  (with-temp-buffer
    (insert sns-roam-test--typed-note)
    (let* ((section (car (org-ml-get-children (org-ml-parse-this-buffer))))
           (table-p (lambda (node) (org-ml-is-type 'table node)))
           (table (seq-find table-p (org-ml-get-children section)))
           (spaced-table (org-ml-set-property :post-blank 2 table))
           (printed (org-ml-to-string spaced-table))
           (edits (sns-roam--section-edits
                   (org-ml-get-children section)
                   (mapcar (lambda (child)
                             (if (eq child table) spaced-table child))
                           (org-ml-get-children section))))
           (edit (car edits))
           (begin (sns-roam--edit-begin edit)))
      (should (= 1 (length edits)))
      (should (equal "\n\n" (plist-get edit :text)))
      (should (string-suffix-p (plist-get edit :text) printed))
      (should (string-suffix-p "|\n" (string-remove-suffix (plist-get edit :text)
                                                          printed)))
      (should (= (org-ml-get-property :end table) (plist-get edit :end)))
      (should (equal "|\n" (buffer-substring-no-properties (- begin 2) begin)))
      (should (string-blank-p (buffer-substring-no-properties
                               begin (plist-get edit :end)))))))

;;; --- files that do not end with a newline ---

(defmacro sns-roam-test--with-unterminated-note (text &rest body)
  "Run BODY with `file' bound to a registered note whose text is TEXT.
TEXT has no final newline; see `sns-roam-test--with-bare-note'."
  (declare (indent 1))
  `(sns-roam-test--with-bare-note ,text ,@body))

(ert-deftest sns-roam-append-link-after-an-unterminated-source-block ()
  ;; The review of slice 14 wrote `#+END_SRCSee [[id:y][Y]].' here.
  ;; The block gains only a blank line, so it keeps its typed text.
  (sns-roam-test--with-unterminated-note
      ":PROPERTIES:\n:ID: bare-id\n:END:\n#+title: Bare\n#+BEGIN_SRC sh\necho hi\n#+END_SRC"
    (sns-roam-append-link "bare-id" "other-id" "Other" "See " ".")
    (should (equal (concat ":PROPERTIES:\n:ID: bare-id\n:END:\n#+title: Bare\n"
                           "#+BEGIN_SRC sh\necho hi\n#+END_SRC\n\n"
                           "See [[id:other-id][Other]].\n")
                   (sns-roam-test--file-text file)))))

(ert-deftest sns-roam-set-body-after-an-unterminated-title ()
  ;; The review of slice 14 wrote `#+title: XNew body.' here.
  (sns-roam-test--with-unterminated-note
      ":PROPERTIES:\n:ID: bare-id\n:END:\n#+title: X"
    (sns-roam-set-body "bare-id" "New body.")
    (should (equal ":PROPERTIES:\n:ID: bare-id\n:END:\n#+title: X\nNew body.\n"
                   (sns-roam-test--file-text file)))))

(ert-deftest sns-roam-set-keyword-after-an-unterminated-paragraph ()
  ;; The review of slice 14 wrote `Intro.#+filetags: :test:' here.
  (sns-roam-test--with-unterminated-note
      ":PROPERTIES:\n:ID: bare-id\n:END:\n#+title: X\nIntro."
    (sns-roam-set-keyword "bare-id" "FILETAGS" ":test:")
    (let ((text (sns-roam-test--file-text file)))
      (should (string-match-p "^Intro\\.$" text))
      (should (string-match-p "^#\\+filetags: :test:$" text)))))

(ert-deftest sns-roam-update-section-refuses-an-edit-that-reads-back-wrong ()
  ;; An edit whose text would parse as something else is refused before
  ;; the buffer changes.  The forced edit writes a paragraph with no line
  ;; break before the next one, so the two would read back as one.
  (sns-roam-test--with-unterminated-note
      ":PROPERTIES:\n:ID: bare-id\n:END:\n#+title: X\nOne.\n\nTwo.\n"
    (let ((before (sns-roam-test--file-text file)))
      (cl-letf (((symbol-function 'sns-roam--section-edits)
                 (lambda (old-children _new-children)
                   (let ((two (car (last old-children))))
                     (list (list :begin (org-ml-get-property :begin two)
                                 :end   (org-ml-get-property :begin two)
                                 :text  "Merged "))))))
        (let ((data (sns-roam-test--error-data
                     'sns-roam-reparse-mismatch
                     (lambda ()
                       (sns-roam-insert-element
                        "bare-id"
                        (lambda (node) (equal "One." (org-ml-to-trimmed-string node)))
                        (org-ml-build-paragraph "New.")
                        t)))))
          (sns-roam-test--should-have data
                                      :id "bare-id" :file file
                                      :operation 'sns-roam-insert-element)
          ;; Each list starts with the drawer and the title, then the body.
          (should (equal '((paragraph "One.") (paragraph "New.") (paragraph "Two."))
                         (seq-drop (plist-get data :planned) 2)))
          (should (equal '((paragraph "One.") (paragraph "Merged Two."))
                         (seq-drop (plist-get data :actual) 2)))))
      (should (equal before (sns-roam-test--file-text file)))
      (should-not (buffer-modified-p (get-file-buffer file))))))

;;; --- every failure site raises its condition with its facts (slice 21) ---

(ert-deftest sns-roam-excerpt-at-a-headline-reports-no-container ()
  (sns-roam-test--with-bare-note
      ":PROPERTIES:\n:ID: bare-id\n:END:\n#+title: Bare\n* Heading\nUnder it.\n"
    (let ((point (with-temp-buffer
                   (insert before)
                   (goto-char (point-min))
                   (search-forward "Heading"))))
      (sns-roam-test--should-have
       (sns-roam-test--error-data 'sns-roam-no-excerpt-container
                                  (lambda () (sns-roam-excerpt "bare-id" point)))
       :id "bare-id" :point point :file file))))

(defconst sns-roam-test--headline-id-note
  "#+title: Headless\nIntro.\n* Heading\n:PROPERTIES:\n:ID: heading-id\n:END:\nUnder it.\n"
  "A note whose only ID is on a heading, so its first section has no drawer.")

(ert-deftest sns-roam-set-property-reports-a-section-with-no-drawer ()
  (sns-roam-test--with-bare-note sns-roam-test--headline-id-note
    (sns-roam-test--should-have
     (sns-roam-test--error-data
      'sns-roam-malformed-note
      (lambda () (sns-roam-set-property "heading-id" "KIND" "reference")))
     :id "heading-id" :file file :missing 'property-drawer :key "KIND"
     :operation 'sns-roam-set-property)
    (should (equal before (sns-roam-test--file-text file)))))

(ert-deftest sns-roam-set-body-reports-a-note-with-no-first-section ()
  (sns-roam-test--with-bare-note
      "* Heading\n:PROPERTIES:\n:ID: heading-id\n:END:\nUnder it.\n"
    (sns-roam-test--should-have
     (sns-roam-test--error-data
      'sns-roam-malformed-note
      (lambda () (sns-roam-set-body "heading-id" "New body.")))
     :id "heading-id" :file file :missing 'section
     :operation 'sns-roam-set-body)
    (should (equal before (sns-roam-test--file-text file)))))

(ert-deftest sns-roam-replace-element-reports-two-matches ()
  (sns-roam-test--with-reference-note
      "2026-10-24: offered terms.\n\n2026-10-30: asked for a discount.\n"
    (let ((state-before (sns-roam-test--file-state file)))
      (sns-roam-test--should-have
       (sns-roam-test--error-data
        'sns-roam-match-count
        (lambda ()
          (sns-roam-replace-element "contract-id"
                                    (sns-roam-test--containing "2026-10")
                                    (org-ml-build-paragraph "Replaced."))))
       :id "contract-id" :file file
       :operation 'sns-roam-replace-element :count 2)
      (should (equal state-before (sns-roam-test--file-state file))))))

(ert-deftest sns-roam-insert-element-reports-an-element-org-prints-otherwise ()
  ;; Org prints every element it parses with its blank lines after its
  ;; text, so no note reaches this refusal.  The stub makes org print a
  ;; table with no blank lines as other text, which is the only call
  ;; the refusal depends on.
  (sns-roam-test--with-bare-note
      ":PROPERTIES:\n:ID: bare-id\n:END:\n#+title: Bare\nIntro.\n\n|a|b|\nOutro.\n"
    (let* ((print (symbol-function 'org-ml-to-string))
           (data (cl-letf (((symbol-function 'org-ml-to-string)
                            (lambda (node)
                              (if (and (org-ml-is-type 'table node)
                                       (eql 0 (org-ml-get-property :post-blank node)))
                                  (concat "# " (funcall print node))
                                (funcall print node)))))
                   (sns-roam-test--error-data
                    'sns-roam-unsupported-element
                    (lambda ()
                      (sns-roam-insert-element "bare-id"
                                               (sns-roam-test--containing "| a | b |")
                                               (org-ml-build-paragraph "New.")
                                               t))))))
      (sns-roam-test--should-have data
                                  :id "bare-id" :file file
                                  :operation 'sns-roam-insert-element
                                  :type 'table)
      (should (equal before (sns-roam-test--file-text file))))))

(ert-deftest sns-roam-rename-file-reports-a-file-not-named-timestamp-slug ()
  (sns-roam-test--with-bare-note
      ":PROPERTIES:\n:ID: bare-id\n:END:\n#+title: Bare\n"
    (sns-roam-test--should-have
     (sns-roam-test--error-data 'sns-roam-malformed-note
                                (lambda () (sns-roam-rename-file "bare-id" "new")))
     :id "bare-id" :file file :missing 'roam-filename :name "bare.org")
    (should (file-exists-p file))))

(ert-deftest sns-roam-rename-file-refuses-a-name-another-file-has ()
  (sns-roam-test--with-typed-note
    (let ((taken (expand-file-name "20261111090000-taken.org" org-roam-directory)))
      (with-temp-file taken
        (insert "Someone else's note.\n"))
      (sns-roam-test--should-have
       (sns-roam-test--error-data 'sns-roam-file-exists
                                  (lambda () (sns-roam-rename-file "typed-id" "taken")))
       :id "typed-id" :path taken)
      (should (equal before (sns-roam-test--file-text file))))))

(ert-deftest sns-roam-rename-file-refuses-the-name-it-has ()
  ;; The note's own file exists, so the overwrite check before this one
  ;; refuses first and no note reaches it.  The stub reports that no
  ;; file exists, which is the only call before the refusal.
  (sns-roam-test--with-typed-note
    (sns-roam-test--should-have
     (cl-letf (((symbol-function 'sns-roam--node-file-or-error)
                (lambda (_id) file))
               ((symbol-function 'file-exists-p) #'ignore))
       (sns-roam-test--error-data
        'sns-roam-file-exists
        (lambda () (sns-roam-rename-file "typed-id" "typed_note"))))
     :id "typed-id" :path file :slug "typed_note")
    (should (equal before (sns-roam-test--file-text file)))))

(ert-deftest sns-roam-rename-reports-a-node-gone-after-the-title-write ()
  ;; A node vanishes between the title write and the lookup only if the
  ;; database changes between them.  The stub makes the title write,
  ;; the call before the lookup, do nothing for an ID with no node.
  (sns-roam-test--with-roam-dir
    (sns-roam-test--should-have
     (cl-letf (((symbol-function 'sns-roam-set-keyword) #'ignore))
       (sns-roam-test--error-data
        'sns-roam-unknown-id
        (lambda () (sns-roam-rename "missing-id" "New title"))))
     :id "missing-id")))

;;; --- a note narrowed in Emacs (slice 23) ---

(defconst sns-roam-test--narrowed-note
  (concat ":PROPERTIES:\n:ID: bare-id\n:END:\n#+title: Narrowed\n\n"
          "Top paragraph.\n\n"
          "* History\n2026-11-06: offered terms.\n")
  "A note with a paragraph before `* History', the subtree the owner narrows to.")

(defun sns-roam-test--history-subtree (file)
  "Return (POINT-MIN . POINT-MAX) of a fresh `org-narrow-to-subtree' on `* History'.
Works in the buffer visiting FILE and leaves its narrowing and point
as they were."
  (with-current-buffer (find-file-noselect file)
    (save-excursion
      (save-restriction
        (widen)
        (goto-char (point-min))
        (re-search-forward "^\\* History$")
        (org-narrow-to-subtree)
        (cons (point-min) (point-max))))))

(defun sns-roam-test--narrow-to-history (file)
  "Narrow the buffer visiting FILE to its `* History' subtree, as the owner would."
  (with-current-buffer (find-file-noselect file)
    (goto-char (point-min))
    (re-search-forward "^\\* History$")
    (org-narrow-to-subtree)))

(defun sns-roam-test--restriction (file)
  "Return (POINT-MIN . POINT-MAX) of the buffer visiting FILE."
  (with-current-buffer (find-file-noselect file)
    (cons (point-min) (point-max))))

(defun sns-roam-test--should-hold-new-top (file)
  "Show FILE holds \"New top.\" before `* History', with that subtree unchanged.
The blank line between them is not checked: an edit of the last body
element drops it whether or not the note is narrowed."
  (let ((text (sns-roam-test--file-text file)))
    (should (string-match-p
             "^#\\+title: Narrowed\n\nNew top\\.\n\n?\\* History\n2026-11-06: offered terms\\.\n\\'"
             text))
    (should-not (string-match-p "Top paragraph" text))))

(ert-deftest sns-roam-body-elements-reads-a-note-narrowed-to-a-subtree ()
  ;; S23.1.  On 2026-11-11 this note read back with no paragraphs
  ;; (issue #12).
  (sns-roam-test--with-bare-note sns-roam-test--narrowed-note
    (sns-roam-test--narrow-to-history file)
    (should (equal '("Top paragraph.")
                   (sns-roam-test--element-texts
                    (sns-roam-body-elements "bare-id"))))
    (should (equal (sns-roam-test--history-subtree file)
                   (sns-roam-test--restriction file)))))

(ert-deftest sns-roam-set-body-edits-a-note-narrowed-to-a-subtree ()
  ;; On 2026-11-11 this edit was refused as a note with no top-level
  ;; section (issue #12).
  (sns-roam-test--with-bare-note sns-roam-test--narrowed-note
    (sns-roam-test--narrow-to-history file)
    (sns-roam-set-body "bare-id" "New top.")
    (sns-roam-test--should-hold-new-top file)
    (should (equal (sns-roam-test--history-subtree file)
                   (sns-roam-test--restriction file)))))

(ert-deftest sns-roam-replace-element-edits-a-note-narrowed-to-a-subtree ()
  ;; S23.2
  (sns-roam-test--with-bare-note sns-roam-test--narrowed-note
    (sns-roam-test--narrow-to-history file)
    (sns-roam-replace-element "bare-id"
                              (sns-roam-test--containing "Top paragraph.")
                              (org-ml-build-paragraph "New top."))
    (sns-roam-test--should-hold-new-top file)
    (should (equal (sns-roam-test--history-subtree file)
                   (sns-roam-test--restriction file)))))

(ert-deftest sns-roam-history-anchor-reads-all-of-a-narrowed-history ()
  ;; Narrowed to the oldest line, the parse would see only that line
  ;; and place a new newest line before it.
  (sns-roam-test--with-reference-note sns-roam-test--history-body
    (let ((region (with-current-buffer (find-file-noselect file)
                    (goto-char (point-min))
                    (re-search-forward "^2026-11-06: ")
                    (narrow-to-region (line-beginning-position) (point-max))
                    (cons (point-min) (point-max)))))
      (should (equal '("2026-11-09: asked for a discount (email from the vendor)." nil)
                     (let ((result (sns-roam-history-anchor "contract-id" "2026-11-12")))
                       (list (plist-get result :anchor) (plist-get result :after)))))
      (should (equal region (sns-roam-test--restriction file))))))

(ert-deftest sns-roam-replace-element-refusal-keeps-a-narrowed-note-as-it-was ()
  ;; Slice 14: a refused edit leaves the buffer and its narrowing alone.
  (sns-roam-test--with-bare-note
      (string-replace "Top paragraph.\n"
                      "Top paragraph.\n\nSecond paragraph.\n"
                      sns-roam-test--narrowed-note)
    (sns-roam-test--narrow-to-history file)
    (let ((restriction (sns-roam-test--restriction file)))
      (sns-roam-test--should-have
       (sns-roam-test--error-data
        'sns-roam-match-count
        (lambda ()
          (sns-roam-replace-element "bare-id"
                                    (sns-roam-test--containing " paragraph.")
                                    (org-ml-build-paragraph "New top."))))
       :count 2)
      (should-not (buffer-modified-p (get-file-buffer file)))
      (should (equal before (sns-roam-test--file-text file)))
      (should (equal restriction (sns-roam-test--restriction file)))
      (should (equal (sns-roam-test--history-subtree file) restriction)))))

(ert-deftest sns-roam-replace-element-keeps-a-narrowing-on-the-edited-paragraph ()
  ;; The narrowing grows with the longer paragraph written in its place.
  (sns-roam-test--with-bare-note sns-roam-test--narrowed-note
    (with-current-buffer (find-file-noselect file)
      (goto-char (point-min))
      (re-search-forward "^Top paragraph\\.$")
      (narrow-to-region (line-beginning-position) (line-end-position)))
    (sns-roam-replace-element "bare-id"
                              (sns-roam-test--containing "Top paragraph.")
                              (org-ml-build-paragraph "A longer new top paragraph."))
    (should (equal "A longer new top paragraph."
                   (with-current-buffer (get-file-buffer file)
                     (string-trim (buffer-string)))))))

;;; --- each edit returns a diff of the note (slice 24) ---

(defun sns-roam-test--diff-lines (diff)
  "Return the lines DIFF removes and adds, as (:removed R :added A).
DIFF is `diff -u' output.  Its `---' and `+++' headers and its `@@'
hunk lines are left out, and each line loses its leading `-' or `+'."
  (let ((lines (seq-remove (lambda (line)
                             (string-match-p "\\`\\(?:---\\|\\+\\+\\+\\) " line))
                           (split-string diff "\n"))))
    (list :removed (mapcar (lambda (line) (substring line 1))
                           (seq-filter (lambda (line) (string-prefix-p "-" line))
                                       lines))
          :added (mapcar (lambda (line) (substring line 1))
                         (seq-filter (lambda (line) (string-prefix-p "+" line))
                                     lines)))))

(defun sns-roam-test--should-name-file (diff file)
  "Show both headers of DIFF name FILE, not a temporary file."
  (should (string-match-p (concat "^--- " (regexp-quote file) "$") diff))
  (should (string-match-p (concat "^\\+\\+\\+ " (regexp-quote file) "$") diff)))

(ert-deftest sns-roam-replace-element-diff-shows-a-lost-line ()
  ;; S24.1.  On 2026-11-10 this edit dropped the second line, returned
  ;; success, and only a manual diff showed it (issue #10).
  (sns-roam-test--with-reference-note
      "Open: renewal date.\nHistory, newest first:\n"
    (let ((result (sns-roam-replace-element
                   "contract-id"
                   (sns-roam-test--containing "Open: renewal date.")
                   (org-ml-build-paragraph "Open: renewal date."))))
      (sns-roam-test--should-have result :id "contract-id" :file file)
      (should (string-match-p "^-History, newest first:$"
                              (plist-get result :diff)))
      (sns-roam-test--should-name-file (plist-get result :diff) file))))

(ert-deftest sns-roam-set-property-to-its-value-gives-an-empty-diff ()
  ;; S24.2.
  (sns-roam-test--with-reference-note "Open: renewal date.\n"
    (sns-roam-test--should-have
     (sns-roam-set-property "contract-id" "KIND" "reference")
     :id "contract-id" :file file :diff "")))

(ert-deftest sns-roam-diff-result-reports-a-diff-that-failed ()
  ;; `diff' exits 2 on trouble, such as a file it cannot read.
  (should (equal "" (sns-roam--diff-result 0 "" "note.org")))
  (should (equal "+a\n" (sns-roam--diff-result 1 "+a\n" "note.org")))
  (sns-roam-test--should-have
   (sns-roam-test--error-data
    'sns-roam-diff-failure
    (lambda () (sns-roam--diff-result 2 "diff: missing" "note.org")))
   :status 2 :output "diff: missing" :file "note.org"))

(ert-deftest sns-roam-set-body-diff-shows-the-body-it-replaced ()
  (sns-roam-test--with-typed-note
    (let* ((result (sns-roam-set-body "typed-id" "New intro.\n\n"))
           (diff (plist-get result :diff)))
      (sns-roam-test--should-have result :id "typed-id" :file file)
      (should (equal '(:removed ("Intro." "|a|b|" "" "+  item one" ""
                                 "#+BEGIN_SRC sh" "echo hi" "#+END_SRC" "")
                       :added ("New intro."))
                     (sns-roam-test--diff-lines diff)))
      (sns-roam-test--should-name-file diff file))))

(ert-deftest sns-roam-replace-element-diff-shows-the-replaced-paragraph ()
  (sns-roam-test--with-typed-note
    (let ((result (sns-roam-replace-element
                   "typed-id"
                   (lambda (node) (equal "Intro." (org-ml-to-trimmed-string node)))
                   (org-ml-build-paragraph :post-blank 1 "New intro."))))
      (sns-roam-test--should-have result :id "typed-id" :file file)
      (should (equal '(:removed ("Intro.") :added ("New intro."))
                     (sns-roam-test--diff-lines (plist-get result :diff)))))))

(ert-deftest sns-roam-insert-element-diff-shows-the-new-paragraph ()
  (sns-roam-test--with-typed-note
    (let ((result (sns-roam-insert-element "typed-id"
                                           (sns-roam-test--containing "Intro.")
                                           (org-ml-build-paragraph "Added.")
                                           t)))
      (sns-roam-test--should-have result :id "typed-id" :file file)
      (should (equal '(:removed () :added ("Added." ""))
                     (sns-roam-test--diff-lines (plist-get result :diff)))))))

(ert-deftest sns-roam-append-link-diff-shows-the-link-paragraph ()
  (sns-roam-test--with-typed-note
    (let ((result (sns-roam-append-link "typed-id" "other-id" "Other" "See " ".")))
      (sns-roam-test--should-have result :from "typed-id" :to "other-id" :file file)
      (should (equal '(:removed () :added ("See [[id:other-id][Other]]." ""))
                     (sns-roam-test--diff-lines (plist-get result :diff)))))))

(ert-deftest sns-roam-set-property-diff-shows-the-changed-drawer-line ()
  (sns-roam-test--with-typed-note
    (let* ((result (sns-roam-set-property "typed-id" "KIND" "permanent"))
           (changed (sns-roam-test--diff-lines (plist-get result :diff))))
      (sns-roam-test--should-have result :id "typed-id" :file file)
      ;; Org prints the whole drawer in its own form, so `:ID:' may
      ;; change its spacing too; every changed line is a drawer line.
      (should (seq-some (apply-partially #'string-match-p "\\`:KIND: +fleeting\\'")
                        (plist-get changed :removed)))
      (should (seq-some (apply-partially #'string-match-p "\\`:KIND: +permanent\\'")
                        (plist-get changed :added)))
      (should (seq-every-p (apply-partially #'string-match-p "\\`:[A-Z]+: +")
                           (append (plist-get changed :removed)
                                   (plist-get changed :added)))))))

(ert-deftest sns-roam-set-keyword-diff-shows-the-changed-keyword-line ()
  (sns-roam-test--with-typed-note
    (let ((result (sns-roam-set-keyword "typed-id" "TITLE" "Retitled note")))
      (sns-roam-test--should-have result :id "typed-id" :file file)
      (should (equal '(:removed ("#+title: Typed note")
                       :added ("#+title: Retitled note"))
                     (sns-roam-test--diff-lines (plist-get result :diff)))))))

(ert-deftest sns-roam-rename-diff-shows-the-new-title-line ()
  ;; The owner's Emacs runs the autosync mode, which records the new
  ;; title on save; the slug of the new name is made from it.
  (sns-roam-test--with-typed-note
    (org-roam-db-autosync-mode 1)
    (unwind-protect
        (let ((result (sns-roam-rename "typed-id" "Renamed note")))
          (sns-roam-test--should-have
           result
           :id "typed-id" :title "Renamed note"
           :file (expand-file-name "20261111090000-renamed_note.org"
                                   org-roam-directory))
          (should (equal '(:removed ("#+title: Typed note")
                           :added ("#+title: Renamed note"))
                         (sns-roam-test--diff-lines (plist-get result :diff)))))
      (org-roam-db-autosync-mode -1))))

;;; --- tags under the title (slice 26) ---

(defconst sns-roam-test--untagged-note
  (concat ":PROPERTIES:\n:ID: bare-id\n:END:\n#+title: Leading teams\n"
          "First paragraph.\n\nSecond paragraph.\n")
  "A note with a title and two paragraphs, and no tags.")

(defun sns-roam-test--text-after-title (file)
  "Return the text of FILE from the line after its #+title: line."
  (let ((text (sns-roam-test--file-text file)))
    (unless (string-match "^#\\+title: .*\n" text)
      (error "sns-roam tests: %s has no #+title: line" file))
    (substring text (match-end 0))))

(ert-deftest sns-roam-set-tags-adds-only-the-line-under-the-title ()
  ;; S26.1.  On 2026-11-12 the line went after the body (issue #19).
  (sns-roam-test--with-bare-note sns-roam-test--untagged-note
    (org-roam-db-autosync-mode 1)
    (unwind-protect
        (let ((result (sns-roam-set-tags "bare-id" '("tech_leadership"))))
          (should (equal '(:removed () :added ("#+filetags: :tech_leadership:"))
                         (sns-roam-test--changed-lines
                          before (sns-roam-test--file-text file))))
          (should (equal '(:removed () :added ("#+filetags: :tech_leadership:"))
                         (sns-roam-test--diff-lines (plist-get result :diff))))
          (should (equal (concat "#+filetags: :tech_leadership:\n"
                                 "First paragraph.\n\nSecond paragraph.\n")
                         (sns-roam-test--text-after-title file)))
          ;; The roam-fetch seed stage finds the note by its new tag.
          (should (equal '("bare-id")
                         (mapcar (lambda (hit) (plist-get hit :id))
                                 (sns-roam-find-by-metadata "tech_leadership")))))
      (org-roam-db-autosync-mode -1))))

(ert-deftest sns-roam-set-tags-moves-a-line-left-after-the-body ()
  ;; S26.2.  `sns-roam-set-keyword' left the line after the body.  A
  ;; moved line differs at both ends, so `sns-roam-test--changed-lines'
  ;; would report the paragraphs between; the line diff shows the move.
  (sns-roam-test--with-bare-note sns-roam-test--untagged-note
    (sns-roam-set-keyword "bare-id" "FILETAGS" ":old:")
    (let ((tagged-after-body (sns-roam-test--file-text file)))
      (should (string-suffix-p "Second paragraph.\n#+filetags: :old:\n"
                               tagged-after-body))
      (let ((result (sns-roam-set-tags "bare-id" '("new"))))
        (should (equal '(:removed ("#+filetags: :old:")
                         :added ("#+filetags: :new:"))
                       (sns-roam-test--diff-lines (plist-get result :diff))))
        (should (equal (concat "#+filetags: :new:\n"
                               "First paragraph.\n\nSecond paragraph.\n")
                       (sns-roam-test--text-after-title file)))))))

(ert-deftest sns-roam-set-tags-refuses-a-tag-org-does-not-read ()
  ;; S26.3.  A hyphen is not in `org-tag-re', so org would not read
  ;; `tech-leadership' as one tag.
  (sns-roam-test--with-bare-note sns-roam-test--untagged-note
    (sns-roam-test--should-have
     (sns-roam-test--error-data
      'sns-roam-bad-tag
      (lambda () (sns-roam-set-tags "bare-id" '("tech-leadership"))))
     :tag "tech-leadership" :id "bare-id" :operation 'sns-roam-set-tags)
    (should (equal before (sns-roam-test--file-text file)))))

(ert-deftest sns-roam-set-tags-names-the-first-bad-tag-and-writes-nothing ()
  (sns-roam-test--with-bare-note sns-roam-test--untagged-note
    (sns-roam-test--should-have
     (sns-roam-test--error-data
      'sns-roam-bad-tag
      (lambda () (sns-roam-set-tags "bare-id" '("research" "tech-leadership"))))
     :tag "tech-leadership")
    (should (equal before (sns-roam-test--file-text file)))))

(ert-deftest sns-roam-set-tags-writes-several-tags-on-one-line ()
  (sns-roam-test--with-bare-note sns-roam-test--untagged-note
    (sns-roam-set-tags "bare-id" '("a" "b_2"))
    (should (equal (concat "#+filetags: :a:b_2:\n"
                           "First paragraph.\n\nSecond paragraph.\n")
                   (sns-roam-test--text-after-title file)))))

(ert-deftest sns-roam-set-tags-twice-leaves-one-line ()
  ;; The second call replaces the line under the title in place.
  (sns-roam-test--with-bare-note sns-roam-test--untagged-note
    (sns-roam-set-tags "bare-id" '("first"))
    (let ((result (sns-roam-set-tags "bare-id" '("second"))))
      (should (equal '(:removed ("#+filetags: :first:")
                       :added ("#+filetags: :second:"))
                     (sns-roam-test--diff-lines (plist-get result :diff)))))
    (should (equal (concat "#+filetags: :second:\n"
                           "First paragraph.\n\nSecond paragraph.\n")
                   (sns-roam-test--text-after-title file)))
    ;; The same tags again change nothing.
    (should (equal "" (plist-get (sns-roam-set-tags "bare-id" '("second")) :diff)))))

(ert-deftest sns-roam-set-tags-with-no-tags-removes-only-the-line ()
  (sns-roam-test--with-bare-note sns-roam-test--untagged-note
    (sns-roam-set-tags "bare-id" '("tech_leadership"))
    (let ((tagged (sns-roam-test--file-text file))
          (result (sns-roam-set-tags "bare-id" '())))
      (should (equal '(:removed ("#+filetags: :tech_leadership:") :added ())
                     (sns-roam-test--changed-lines
                      tagged (sns-roam-test--file-text file))))
      (should (equal '(:removed ("#+filetags: :tech_leadership:") :added ())
                     (sns-roam-test--diff-lines (plist-get result :diff))))
      (should (equal before (sns-roam-test--file-text file))))))

(ert-deftest sns-roam-set-tags-keeps-the-gap-after-the-title ()
  ;; The new line takes the title's blank line, so the title and the
  ;; tags share no blank line and the body keeps its gap.
  (sns-roam-test--with-bare-note
      ":PROPERTIES:\n:ID: bare-id\n:END:\n#+title: Spaced\n\nBody.\n"
    (sns-roam-set-tags "bare-id" '("a"))
    (should (equal "#+filetags: :a:\n\nBody.\n"
                   (sns-roam-test--text-after-title file)))
    (sns-roam-set-tags "bare-id" '())
    (should (equal before (sns-roam-test--file-text file)))))

(ert-deftest sns-roam-set-tags-refuses-a-note-with-no-title ()
  (sns-roam-test--with-bare-note
      ":PROPERTIES:\n:ID: bare-id\n:END:\nBody.\n"
    (sns-roam-test--should-have
     (sns-roam-test--error-data
      'sns-roam-malformed-note
      (lambda () (sns-roam-set-tags "bare-id" '("a"))))
     :missing 'title :key "TITLE" :id "bare-id")
    (should (equal before (sns-roam-test--file-text file)))))

(ert-deftest sns-roam-create-node-writes-tags-under-the-title ()
  (sns-roam-test--with-roam-dir
    (let ((file (plist-get (sns-roam-create-node
                            "Leading teams" "permanent"
                            (sns-roam--parse-body-elements "Body.\n")
                            nil nil nil nil '("tech_leadership"))
                           :file)))
      (should (equal "#+filetags: :tech_leadership:\nBody.\n"
                     (sns-roam-test--text-after-title file)))
      (should (equal '("tech_leadership")
                     (plist-get (car (sns-roam-find-by-metadata "tech_leadership"))
                                :tags))))))

(ert-deftest sns-roam-create-node-writes-several-tags-on-one-line ()
  (sns-roam-test--with-roam-dir
    (let ((file (plist-get (sns-roam-create-node "Lettered" "permanent" nil
                                                 nil nil nil nil '("a" "b_2"))
                           :file)))
      (should (equal "#+filetags: :a:b_2:\n"
                     (sns-roam-test--text-after-title file))))))

(ert-deftest sns-roam-new-note-content-puts-tags-under-the-title ()
  ;; The layout is a calculation: no file, clock or database is needed
  ;; to see where the tag line, the body and the headlines go.
  (should (equal (concat ":PROPERTIES:\n:ID:       fixed-id\n"
                         ":CREATED:  [2026-11-12 Thu 09:00]\n:KIND:     permanent\n"
                         ":ROAM_ALIASES: \"Leading\"\n:END:\n"
                         "#+title: Leading teams\n#+filetags: :a:b_2:\n"
                         "First.\n\nSecond.\n* Later\n")
                 (sns-roam--new-note-content
                  (list :id "fixed-id" :title "Leading teams" :kind "permanent"
                        :created "[2026-11-12 Thu 09:00]" :aliases '("Leading")
                        :tags '("a" "b_2")
                        :elements (list (org-ml-build-paragraph "First.")
                                        (org-ml-build-paragraph "Second.")
                                        (org-ml-build-headline :title '("Later")))))))
  (should (equal (concat ":PROPERTIES:\n:ID:       fixed-id\n"
                         ":CREATED:  [2026-11-12 Thu 09:00]\n:KIND:     permanent\n:END:\n"
                         "#+title: Untagged\n")
                 (sns-roam--new-note-content
                  (list :id "fixed-id" :title "Untagged" :kind "permanent"
                        :created "[2026-11-12 Thu 09:00]")))))

(ert-deftest sns-roam-create-node-refuses-a-bad-tag-and-leaves-no-file ()
  (sns-roam-test--with-roam-dir
    (sns-roam-test--should-have
     (sns-roam-test--error-data
      'sns-roam-bad-tag
      (lambda () (sns-roam-create-node "Leading teams" "permanent" nil
                                       nil nil nil nil '("tech-leadership"))))
     :tag "tech-leadership")
    (sns-roam-test--should-have
     (sns-roam-test--error-data
      'sns-roam-bad-tag
      (lambda () (sns-roam-create-node "Leading teams" "permanent" nil
                                       nil nil nil nil
                                       '("research" "tech-leadership"))))
     :tag "tech-leadership")
    (should (equal nil (sns-roam-test--org-files)))
    (should (equal nil (org-roam-db-query [:select * :from nodes])))))

;;; --- each Contract against the code ---

(defconst sns-roam-test--source-file
  (expand-file-name "../src/roam-api.org"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "The literate source whose Contracts the contract tests read.")

(defconst sns-roam-test--write-boundary
  '(sns-roam--update-section . "those of the write boundary")
  "The write boundary, and the phrase a Contract inherits its errors by.")

(defconst sns-roam-test--contracts
  `((sns-roam-find-by-metadata
     :returns (:id :title :file :tags :aliases) :names () :inherits ())
    (sns-roam-body-search
     :returns (:id :title :file :line :point :hit-text) :names () :inherits ())
    (sns-roam-expand
     :returns (:nodes :edges)
     :names (sns-roam-unknown-id sns-roam-missing-file) :inherits ())
    (sns-roam-excerpt
     :returns (:id :file :point :text :container-type :outline)
     :names (sns-roam-unknown-id sns-roam-missing-file
             sns-roam-no-excerpt-container)
     :inherits ())
    (sns-roam--update-section
     :opening "keeps this contract:$"
     :returns (:id :file :diff)
     :names (sns-roam-unknown-id sns-roam-missing-file sns-roam-malformed-note
             sns-roam-unsupported-element sns-roam-reparse-mismatch
             sns-roam-diff-failure)
     :inherits ())
    (sns-roam-set-property
     :returns (:id :file :diff)
     :names (sns-roam-malformed-note) :inherits (,sns-roam-test--write-boundary))
    (sns-roam-set-body
     :returns (:id :file :diff)
     :names () :inherits (,sns-roam-test--write-boundary))
    (sns-roam-append-link
     :returns (:from :to :file :diff)
     :names (sns-roam-unknown-id sns-roam-missing-file)
     :inherits (,sns-roam-test--write-boundary))
    (sns-roam-body-elements
     :returns (:id :file :elements)
     :names (sns-roam-unknown-id sns-roam-missing-file) :inherits ())
    (sns-roam-replace-element
     :returns (:id :file :diff)
     :names (sns-roam-match-count sns-roam-diff-failure)
     :inherits (,sns-roam-test--write-boundary))
    (sns-roam-insert-element
     :returns (:id :file :diff)
     :names (sns-roam-unsupported-element sns-roam-match-count
             sns-roam-reparse-mismatch sns-roam-unknown-id sns-roam-missing-file
             sns-roam-malformed-note sns-roam-diff-failure)
     :inherits (,sns-roam-test--write-boundary))
    (sns-roam-history-anchor
     :returns (:id :file :anchor :after)
     :names (sns-roam-unknown-id sns-roam-missing-file sns-roam-bad-date
             sns-roam-unsupported-element sns-roam-history-layout
             sns-roam-match-count)
     :inherits ())
    (sns-roam-set-keyword
     :returns (:id :file :diff)
     :names () :inherits (,sns-roam-test--write-boundary))
    (sns-roam-set-tags
     :returns (:id :file :diff)
     :names (sns-roam-bad-tag sns-roam-malformed-note)
     :inherits (,sns-roam-test--write-boundary))
    (sns-roam-rename-file
     :returns path
     :names (sns-roam-unknown-id sns-roam-missing-file sns-roam-malformed-note
             sns-roam-file-exists)
     :inherits ())
    (sns-roam-rename
     :returns (:id :title :file :diff)
     :names (sns-roam-unknown-id sns-roam-file-exists)
     :inherits ((sns-roam-set-keyword . "those of =sns-roam-set-keyword=")
                (sns-roam-rename-file . "those of =sns-roam-rename-file=")))
    (sns-roam-create-node
     :returns (:id :title :file)
     :names (sns-roam-bad-tag sns-roam-file-exists sns-roam-id-conflict
             sns-roam-index-failure)
     :inherits ())
    (sns-roam-meeting-note
     :returns (:id :title :file)
     :names ()
     :inherits ((sns-roam-create-node . "those of =sns-roam-create-node="))))
  "What each public function's Contract in the literate source states.
Each entry is (FUNCTION :returns KEYS :names KINDS :inherits PAIRS).
KEYS are the keys of the plist the function returns, in order, or the
symbol `path' for a function that returns a file name.  KINDS are the
error kinds the Contract names.  PAIRS are (FUNCTION . PHRASE): the
Contract states the errors of FUNCTION too, in words containing PHRASE.
An entry's :opening, when present, is the regexp the Contract text
starts after, for the write boundary, whose Contract sits in another
function's section.  The write boundary is private, but every edit
inherits its Contract.")

(defun sns-roam-test--contract-entry (function)
  "Return the `sns-roam-test--contracts' plist for FUNCTION."
  (or (alist-get function sns-roam-test--contracts)
      (error "sns-roam tests: no Contract entry for %s" function)))

(defun sns-roam-test--contract-text (function)
  "Return the Contract text for FUNCTION in `sns-roam-test--source-file'.
The Contract is in the top-level section that defines FUNCTION.  It
starts after the line \"** Contract\", or after the entry's :opening,
and ends at the next heading or source block."
  (with-temp-buffer
    (insert-file-contents sns-roam-test--source-file)
    (goto-char (point-min))
    (unless (re-search-forward
             (format "^(defun %s " (regexp-quote (symbol-name function))) nil t)
      (error "sns-roam tests: %s is not defined in the source" function))
    (re-search-backward "^\\* ")
    (let ((section-end (save-excursion
                         (forward-line)
                         (if (re-search-forward "^\\* " nil t)
                             (match-beginning 0)
                           (point-max))))
          (opening (or (plist-get (sns-roam-test--contract-entry function)
                                  :opening)
                       "^\\*\\* Contract$")))
      (unless (re-search-forward opening section-end t)
        (error "sns-roam tests: no Contract for %s" function))
      (buffer-substring-no-properties
       (point)
       (if (re-search-forward "^\\*\\|^#\\+begin_src" nil t)
           (match-beginning 0)
         (point-max))))))

(defun sns-roam-test--contract-output (function)
  "Return the *Output* item of FUNCTION's Contract text."
  (let ((text (sns-roam-test--contract-text function)))
    (unless (string-match "^- \\*Output\\*" text)
      (error "sns-roam tests: the Contract for %s has no Output" function))
    (let ((start (match-beginning 0)))
      (substring text start (string-match "^- \\*" text (match-end 0))))))

(defun sns-roam-test--kinds-named-in (text)
  "Return each declared error kind that TEXT writes as =KIND=."
  (seq-filter (lambda (kind)
                (string-search (format "=%s=" kind) text))
              sns-roam--error-kinds))

(defun sns-roam-test--stated-kinds (function)
  "Return the error kinds FUNCTION's Contract states, with those it inherits."
  (let ((entry (sns-roam-test--contract-entry function)))
    (seq-uniq
     (append (plist-get entry :names)
             (mapcan (lambda (pair)
                       (sns-roam-test--stated-kinds (car pair)))
                     (plist-get entry :inherits))))))

(defun sns-roam-test--library-definitions ()
  "Return a hash table from each function the library defines to its body.
Reads the forms of `sns-roam-test--api-file' without evaluating them."
  (let ((definitions (make-hash-table :test #'eq)))
    (with-temp-buffer
      (insert-file-contents sns-roam-test--api-file)
      (goto-char (point-min))
      (condition-case nil
          (while t
            (let ((form (read (current-buffer))))
              (when (and (consp form) (eq 'defun (car form)))
                (puthash (nth 1 form) (nthcdr 2 form) definitions))))
        (end-of-file nil)))
    definitions))

(defun sns-roam-test--symbols-in (form)
  "Return every symbol that occurs in FORM, at any depth."
  (cond ((symbolp form) (list form))
        ((consp form) (append (sns-roam-test--symbols-in (car form))
                              (sns-roam-test--symbols-in (cdr form))))
        (t nil)))

(defun sns-roam-test--raisable-kinds (function definitions)
  "Return the error kinds FUNCTION's code can raise, sorted by name.
DEFINITIONS is `sns-roam-test--library-definitions'.  A kind counts
when FUNCTION, or a library function it names, calls its signaller
`sns-roam--signal-KIND', so the count follows every path, taken or
not, and every function passed by name."
  (let ((visited nil)
        (kinds nil)
        (pending (list function)))
    (while pending
      (let ((current (pop pending)))
        (unless (memq current visited)
          (push current visited)
          (dolist (symbol (sns-roam-test--symbols-in (gethash current definitions)))
            (let ((name (symbol-name symbol)))
              (cond
               ((string-prefix-p "sns-roam--signal-" name)
                (cl-pushnew (intern (concat "sns-roam-"
                                            (string-remove-prefix
                                             "sns-roam--signal-" name)))
                            kinds))
               ((gethash symbol definitions)
                (push symbol pending))))))))
    (sort kinds #'string<)))

(defun sns-roam-test--plist-keys (plist)
  "Return the keys of PLIST, in order."
  (cl-loop for (key _value) on plist by #'cddr collect key))

(ert-deftest sns-roam-every-public-function-has-a-contract-entry ()
  ;; A public function added without an entry fails here, so the
  ;; comparisons below cover every one.
  (let ((public (cl-loop for function being the hash-keys
                         of (sns-roam-test--library-definitions)
                         when (and (string-prefix-p "sns-roam-" (symbol-name function))
                                   (not (string-prefix-p "sns-roam--"
                                                         (symbol-name function))))
                         collect function)))
    (should (seq-set-equal-p
             public
             (seq-remove (lambda (function)
                           (string-prefix-p "sns-roam--" (symbol-name function)))
                         (mapcar #'car sns-roam-test--contracts))))))

(ert-deftest sns-roam-each-contract-states-the-entry-it-is-checked-by ()
  ;; The Contract names the entry's error kinds and no other, names
  ;; each contract it inherits from, and gives each return key in its
  ;; Output item.
  (dolist (entry sns-roam-test--contracts)
    (let* ((function (car entry))
           (text (sns-roam-test--contract-text function))
           (output (sns-roam-test--contract-output function))
           (returns (plist-get (cdr entry) :returns)))
      (should (equal (list function (sort (copy-sequence
                                           (plist-get (cdr entry) :names))
                                          #'string<))
                     (list function (sort (sns-roam-test--kinds-named-in text)
                                          #'string<))))
      (dolist (pair (plist-get (cdr entry) :inherits))
        (should (equal (list function (cdr pair))
                       (list function
                             (let ((case-fold-search t))
                               (and (string-match-p (regexp-quote (cdr pair)) text)
                                    (cdr pair)))))))
      (if (eq returns 'path)
          (should (string-match-p "file path" output))
        (dolist (key returns)
          (should (equal (list function key)
                         (list function
                               (and (string-match-p
                                     ;; Org text puts = after a key, which
                                     ;; the syntax table calls part of a
                                     ;; symbol, so test the next character.
                                     (format "%s\\([^-a-z]\\|\\'\\)"
                                             (regexp-quote (symbol-name key)))
                                     output)
                                    key)))))))))

(ert-deftest sns-roam-each-contract-states-the-kinds-its-code-raises ()
  ;; S25.1: the kinds a Contract states, with those it inherits, are the
  ;; kinds its function's code can raise.
  (let ((definitions (sns-roam-test--library-definitions)))
    (dolist (entry sns-roam-test--contracts)
      (let ((function (car entry)))
        (should (equal (list function (sort (sns-roam-test--stated-kinds function)
                                            #'string<))
                       (list function (sns-roam-test--raisable-kinds
                                       function definitions))))))))

(defun sns-roam-test--returned-keys (function result)
  "Return (FUNCTION KEYS), the keys FUNCTION's RESULT holds.
KEYS is `path' when RESULT is a file name, as the Contract entries
write it."
  (list function (if (stringp result) 'path (sns-roam-test--plist-keys result))))

(defun sns-roam-test--stated-keys (function)
  "Return (FUNCTION KEYS), the keys FUNCTION's Contract entry states."
  (list function (plist-get (sns-roam-test--contract-entry function) :returns)))

(ert-deftest sns-roam-each-public-function-returns-the-keys-its-contract-states ()
  ;; S25.1: a call to each function returns the keys its Contract
  ;; states, :diff included for each edit of an existing note.
  (sns-roam-test--with-roam-dir
    (org-roam-db-autosync-mode 1)
    (let* ((tide (sns-roam-create-node
                  "Tide tables" "reference"
                  (sns-roam--parse-body-elements
                   "Current state: calm.\n\n2026-11-01: high water at noon.\n")))
           (moon (sns-roam-create-node
                  "Moon phases" "permanent"
                  (sns-roam--parse-body-elements "The moon pulls the sea.\n")))
           (tide-id (plist-get tide :id))
           (moon-id (plist-get moon :id))
           (calls nil))
      (unwind-protect
          (cl-flet ((record (function result)
                      (push (cons function result) calls)
                      result))
            (record 'sns-roam-create-node tide)
            (record 'sns-roam-find-by-metadata
                    (car (sns-roam-find-by-metadata "Tide")))
            (let ((hit (record 'sns-roam-body-search
                               (car (sns-roam-body-search "high water")))))
              (record 'sns-roam-excerpt
                      (sns-roam-excerpt tide-id (plist-get hit :point))))
            (record 'sns-roam-append-link
                    (sns-roam-append-link moon-id tide-id "tides" "It drives " "."))
            (record 'sns-roam-expand (sns-roam-expand tide-id))
            (record 'sns-roam-body-elements (sns-roam-body-elements tide-id))
            (let ((anchor (record 'sns-roam-history-anchor
                                  (sns-roam-history-anchor tide-id "2026-11-05"))))
              (record 'sns-roam-insert-element
                      (sns-roam-insert-element
                       tide-id
                       (lambda (node)
                         (string= (plist-get anchor :anchor)
                                  (org-ml-to-trimmed-string node)))
                       (org-ml-build-paragraph "2026-11-05: low water at six.")
                       (plist-get anchor :after))))
            (record 'sns-roam-replace-element
                    (sns-roam-replace-element
                     tide-id (sns-roam-test--containing "Current state")
                     (org-ml-build-paragraph :post-blank 1 "Current state: rough.")))
            (record 'sns-roam--update-section
                    (sns-roam--update-section 'sns-roam-test tide-id #'identity))
            (record 'sns-roam-set-property
                    (sns-roam-set-property tide-id "KIND" "permanent"))
            (record 'sns-roam-set-keyword
                    (sns-roam-set-keyword tide-id "FILETAGS" ":sea:"))
            (record 'sns-roam-set-tags
                    (sns-roam-set-tags tide-id '("sea" "tides")))
            (record 'sns-roam-set-body
                    (sns-roam-set-body moon-id "The moon pulls the sea twice a day."))
            (record 'sns-roam-rename-file (sns-roam-rename-file moon-id "lunar_phases"))
            (record 'sns-roam-rename (sns-roam-rename tide-id "Tide charts"))
            (let ((meeting (sns-roam-meeting-note "pir-prep")))
              (sns-roam-test--kill-file-buffer (plist-get meeting :file))
              (record 'sns-roam-meeting-note meeting))
            ;; Each public function and the write boundary was called.
            (should (seq-set-equal-p (mapcar #'car sns-roam-test--contracts)
                                     (delete-dups (mapcar #'car calls))))
            ;; The two searches return lists; their first result stands
            ;; for each, and a missing one fails as a nil result.
            (dolist (call calls)
              (should (cdr call))
              (should (equal (sns-roam-test--stated-keys (car call))
                             (sns-roam-test--returned-keys
                              (car call) (cdr call))))))
        (org-roam-db-autosync-mode -1)
        (dolist (buffer (buffer-list))
          (let ((file (buffer-file-name buffer)))
            (when (and file (string-prefix-p (file-truename org-roam-directory)
                                              (file-truename file)))
              (with-current-buffer buffer
                (set-buffer-modified-p nil))
              (kill-buffer buffer))))))))

(provide 'sns-roam-test)
;;; sns-roam-test.el ends here
