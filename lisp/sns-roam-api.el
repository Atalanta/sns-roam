;;; sns-roam-api.el --- Lisp bridge into the org-roam slipbox -*- lexical-binding: t; -*-
;;
;; Author: Stephen Nelson-Smith <stephen@atalanta-systems.com>
;; Version: 0.1.0
;; Package-Requires: ((emacs "31.1") (org-roam "20260425") (org-ml "20250514") (yaml "20260605"))
;; URL: https://github.com/Atalanta/sns-roam
;; Keywords: outlines, tools
;;
;;; Commentary:
;;
;; This file is generated from roam-api.org. Do not edit directly.
;;
;;; Code:

(require 'org-roam)
(require 'cl-lib)

(defun sns-roam--node-to-plist (node)
  "Convert an `org-roam-node' NODE into a plist for Claude."
  (list :id       (org-roam-node-id node)
        :title    (org-roam-node-title node)
        :file     (org-roam-node-file node)
        :tags     (org-roam-node-tags node)
        :aliases  (org-roam-node-aliases node)))

(defun sns-roam-find-by-metadata (query)
  "Return roam nodes whose title, alias, or tag matches QUERY (substring, case-insensitive).

Each result is a plist of the shape
  (:id ID :title TITLE :file FILE :tags TAGS :aliases ALIASES).
QUERY is a string. Empty list on no match.

Deduped by :id — `org-roam-node-list' returns one entry per
(node, alias) pair, so a node with N aliases would otherwise
appear N+1 times."
  (let ((q (downcase query))
        (seen (make-hash-table :test 'equal))
        (results nil))
    (dolist (node (org-roam-node-list))
      (let* ((id      (org-roam-node-id node))
             (title   (or (org-roam-node-title node) ""))
             (aliases (org-roam-node-aliases node))
             (tags    (org-roam-node-tags node)))
        (when (and (not (gethash id seen))
                   (or (cl-search q (downcase title))
                       (cl-some (lambda (a) (cl-search q (downcase a))) aliases)
                       (cl-some (lambda (tg) (cl-search q (downcase tg))) tags)))
          (puthash id t seen)
          (push (sns-roam--node-to-plist node) results))))
    (nreverse results)))

(defun sns-roam--skip-header ()
  "Move point past the file's =:PROPERTIES:= drawer and =#+title:= line.
Stays at point 1 if no header found. Cheap heuristic: search
forward for =#+title:=, move to the line after; otherwise leave
point at the start of buffer."
  (goto-char (point-min))
  (when (re-search-forward "^#\\+title:.*\n" nil t)
    (goto-char (match-end 0))))

(defun sns-roam--search-file (file query)
  "Return a list of hit plists for QUERY in FILE.
Empty list if no hits or file isn't a roam node."
  (let ((re (regexp-quote query))
        (case-fold-search t)
        (hits nil))
    (with-temp-buffer
      (insert-file-contents file)
      (let ((id (org-with-point-at 1 (org-id-get))))
        (when id
          (let* ((node (org-roam-node-from-id id))
                 (title (when node (org-roam-node-title node))))
            (sns-roam--skip-header)
            (while (re-search-forward re nil t)
              (let* ((point (match-beginning 0))
                     (line  (line-number-at-pos point))
                     (line-text
                      (string-trim
                       (buffer-substring-no-properties
                        (line-beginning-position)
                        (line-end-position)))))
                (push (list :id id
                            :title title
                            :file file
                            :line line
                            :point point
                            :hit-text line-text)
                      hits)))))))
    (nreverse hits)))

(defun sns-roam-body-search (query)
  "Return all body-text matches for QUERY across the roam slipbox.

Each result is a plist of the shape
  (:id ID :title TITLE :file FILE :line LINE :point POINT :hit-text TEXT).

Substring match, case-insensitive. The =:PROPERTIES:= drawer
and =#+title:= line are skipped so UUID/keyword noise doesn't
match. Files without an =:ID:= property drawer (i.e. not a roam
node) are skipped silently. Empty list on no match."
  (let ((files (directory-files-recursively
                org-roam-directory "\\.org\\'")))
    (cl-mapcan (lambda (f) (sns-roam--search-file f query)) files)))

(defun sns-roam--backlink-edges (target-node)
  "Return a list of backlink edge plists pointing at TARGET-NODE."
  (mapcar
   (lambda (bl)
     (let ((source (org-roam-backlink-source-node bl)))
       (list :source-id  (org-roam-node-id source)
             :target-id  (org-roam-node-id target-node)
             :direction  :backward
             :point      (org-roam-backlink-point bl)
             :context    (plist-get (org-roam-backlink-properties bl)
                                    :outline))))
   (org-roam-backlinks-get target-node)))

(defun sns-roam--forward-link-edges (source-node)
  "Return a list of forward-link edge plists from SOURCE-NODE.
Only =id:= links count; fuzzy and external links are skipped."
  (let* ((file   (org-roam-node-file source-node))
         (parsed (with-temp-buffer
                   (insert-file-contents file)
                   (org-mode)
                   (org-ml-parse-this-buffer)))
         (links  (org-ml-match '(:any * link) parsed)))
    (cl-loop for link in links
             when (string= (org-ml-get-property :type link) "id")
             collect
             (let* ((target-id (org-ml-get-property :path link))
                    (children (org-ml-get-children link))
                    (text-raw (and (stringp (car-safe children))
                                   (car children)))
                    (text (and text-raw (substring-no-properties text-raw))))
               (list :source-id  (org-roam-node-id source-node)
                     :target-id  target-id
                     :direction  :forward
                     :point      (org-ml-get-property :begin link)
                     :context    text)))))

(defun sns-roam-expand (id)
  "Return the one-hop subgraph around roam node ID.

Result shape:
  (:nodes (PLIST ...)
   :edges (PLIST ...))

=:nodes= contains every source/target node touched by an edge,
deduped by =:id=, plus the centre node itself. =:edges= contains
all backlinks (=:direction :backward=) and forward links
(=:direction :forward=) as edge plists.

Loud failure if ID has no roam node."
  (let* ((centre (org-roam-node-from-id id))
         (_ (unless centre (error "sns-roam: no roam node with id %S" id)))
         (back-edges (sns-roam--backlink-edges centre))
         (fwd-edges  (sns-roam--forward-link-edges centre))
         (all-edges  (append back-edges fwd-edges))
         (other-ids  (delete-dups
                      (append (mapcar (lambda (e) (plist-get e :source-id)) back-edges)
                              (mapcar (lambda (e) (plist-get e :target-id)) fwd-edges))))
         (other-nodes (mapcar
                       (lambda (oid)
                         (let ((n (org-roam-node-from-id oid)))
                           (if n
                               (sns-roam--node-to-plist n)
                             ;; unresolved id — surface a stub
                             (list :id oid :title nil :file nil
                                   :tags nil :aliases nil))))
                       other-ids))
         (centre-plist (sns-roam--node-to-plist centre)))
    (list :nodes (cons centre-plist other-nodes)
          :edges all-edges)))

(defconst sns-roam--excerpt-container-types
  '(paragraph item quote-block verse-block)
  "Element types that count as excerpt containers for mining.
Walks descend past =plain-list= to its =item= children — the item
is the better excerpt unit than the whole list.")

(defun sns-roam--element-contains-point-p (element point)
  "Return non-nil if POINT lies within ELEMENT's [:begin, :end) window."
  (let ((b (org-ml-get-property :begin element))
        (e (org-ml-get-property :end element)))
    (and b e (<= b point) (< point e))))

(defun sns-roam--ancestry-at-point (root point)
  "Return the ancestry chain of elements containing POINT under ROOT.
Result is root-to-leaf, including ROOT when it contains POINT.
Each element appears once. Pure: no buffer state, no mutation."
  (when (sns-roam--element-contains-point-p root point)
    (cons root
          (cl-loop for child in (org-ml-get-children root)
                   for sub = (and (listp child)
                                  (sns-roam--ancestry-at-point child point))
                   when sub return sub))))

(defun sns-roam--headline-to-plist (h)
  "Convert headline AST node H into a plist for Claude."
  (list :level         (org-ml-get-property :level h)
        :raw-value     (org-ml-get-property :raw-value h)
        :tags          (org-ml-get-property :tags h)
        :todo-keyword  (org-ml-get-property :todo-keyword h)))

(defun sns-roam-excerpt (id point)
  "Return the excerpt container enclosing POINT in roam node ID's file.

Result shape:
  (:id ID
   :file FILE
   :point POINT
   :text TEXT
   :container-type SYMBOL
   :outline (HEADLINE-PLIST ...))

Loud failure if ID is unknown or POINT has no enclosing excerpt
container (=paragraph= / =item= / =quote-block= / =verse-block=).
The latter usually means POINT landed in a headline title line or
a property drawer — fix the upstream caller."
  (let* ((file    (sns-roam--node-file-or-error id))
         (root    (with-temp-buffer
                    (insert-file-contents file)
                    (org-mode)
                    (org-ml-parse-this-buffer)))
         (chain   (sns-roam--ancestry-at-point root point))
         (outline (cl-loop for el in chain
                           when (org-ml-is-type 'headline el)
                           collect (sns-roam--headline-to-plist el)))
         (container
          (cl-loop for el in (reverse chain)
                   when (memq (org-ml-get-type el)
                              sns-roam--excerpt-container-types)
                   return el)))
    (unless container
      (error "sns-roam: point %d in %s has no enclosing excerpt container"
             point file))
    (list :id              id
          :file            file
          :point           point
          :text            (string-trim (org-ml-to-string container))
          :container-type  (org-ml-get-type container)
          :outline         outline)))

(require 'org-ml)

(defun sns-roam--node-file-or-error (id)
  "Return the file path for roam node ID, or signal an error.
Loud failure on unknown ID — never returns nil."
  (let ((node (org-roam-node-from-id id)))
    (unless node
      (error "sns-roam: no roam node with id %S" id))
    (org-roam-node-file node)))

(defun sns-roam--upsert-node-property (drawer key value)
  "Return DRAWER with KEY set to VALUE.
If KEY already present, replace its value; otherwise append a new
node-property as the drawer's last child. Pure — does not mutate."
  (let* ((children (org-ml-get-children drawer))
         (found    nil)
         (updated  (mapcar
                    (lambda (np)
                      (if (and (org-ml-is-type 'node-property np)
                               (string= (org-ml-get-property :key np) key))
                          (progn
                            (setq found t)
                            (org-ml-set-property :value value np))
                        np))
                    children)))
    (org-ml-set-children
     (if found
         updated
       (append updated (list (org-ml-build-node-property key value))))
     drawer)))

(defun sns-roam-set-property (id key value)
  "Set property KEY to VALUE in the top-level drawer of roam node ID.

ID is a roam UUID; KEY is the bare property name (no colons);
VALUE is a string. Returns t on success. Errors if the node is
unknown, or if the file has no top-level section/drawer to
update (which would mean it isn't a well-formed roam file)."
  (let ((file (sns-roam--node-file-or-error id)))
    (with-current-buffer (find-file-noselect file)
      (let* ((tree     (org-ml-parse-this-buffer))
             (section  (car (org-ml-get-children tree))))
        (unless (and section (org-ml-is-type 'section section))
          (error "sns-roam: %s has no top-level section" file))
        (let* ((sec-children (org-ml-get-children section))
               (drawer       (cl-find-if
                              (lambda (c) (org-ml-is-type 'property-drawer c))
                              sec-children)))
          (unless drawer
            (error "sns-roam: %s has no top-level property-drawer" file))
          (let* ((new-drawer   (sns-roam--upsert-node-property drawer key value))
                 (new-section  (org-ml-set-children
                                (mapcar (lambda (c)
                                          (if (eq c drawer) new-drawer c))
                                        sec-children)
                                section))
                 (new-tree     (org-ml-set-children
                                (cons new-section
                                      (cdr (org-ml-get-children tree)))
                                tree)))
            (erase-buffer)
            (insert (org-ml-to-string new-tree))
            (save-buffer)
            t))))))

(defun sns-roam--section-header-p (element)
  "Non-nil if ELEMENT is roam header furniture (property-drawer or keyword)."
  (or (org-ml-is-type 'property-drawer element)
      (org-ml-is-type 'keyword element)))

(defun sns-roam--map-children (fn section)
  "Return SECTION with FN applied to its full child list.
FN takes the section's children (header furniture + body) and
returns a new child list. Pure: returns a new section, mutates
nothing.

IMPORTANT: operate on the child list as a whole — do NOT slice it
into header/body sublists and re-`append` them. Parsed nodes carry
buffer positions and :parent backrefs; reassembling sliced sublists
of parsed nodes corrupts those, and `org-ml-update-this-buffer`'s
reconciliation then fails with `number-or-marker-p`. Filtering the
list in place (e.g. `seq-filter`) is safe; slicing-and-rejoining is
not.

Body helpers are expressed in terms of this:
- append: `(append children NEW)` — header stays in front untouched.
- replace-body: `(append (seq-filter #'sns-roam--section-header-p
  children) NEW-BODY)` — keep header, drop old body, add new."
  (org-ml-map-children fn section))

(defun sns-roam--parse-body-elements (string)
  "Parse STRING of org prose into a list of body elements.
A bare string parses to a single headline-less section; we return
that section's children. Empty STRING yields nil."
  (if (string-empty-p string)
      nil
    (let* ((tree    (with-temp-buffer
                      (insert string)
                      (org-ml-parse-this-buffer)))
           (section (car (org-ml-get-children tree))))
      (if section (org-ml-get-children section) nil))))

(defun sns-roam--update-section (id section-fn)
  "Apply pure SECTION-FN (section -> section) to node ID and save.
The single write boundary for body mutations: parse → transform →
reconcile buffer (`org-ml-update-this-buffer`, minimal-diff) → save.
Loud failure on unknown ID or malformed file. Returns (:id :file)."
  (let ((file (sns-roam--node-file-or-error id)))
    (with-current-buffer (find-file-noselect file)
      (org-ml-update-this-buffer
       (lambda (data)
         (let* ((children (org-ml-get-children data))
                (section  (car children)))
           (unless (and section (org-ml-is-type 'section section))
             (error "sns-roam: %s has no top-level section" file))
           (org-ml-set-children
            (cons (funcall section-fn section) (cdr children))
            data))))
      (save-buffer)
      (list :id id :file file))))

(defun sns-roam-set-body (id new-body)
  "Replace the body of roam node ID with NEW-BODY.

The paragraphs and other body elements before the first heading
are replaced with NEW-BODY parsed as org prose. Property drawers,
standalone =#+= keywords (=#+title:=, =#+filetags:=) and every
existing heading with its content stay. Affiliated keywords
(=#+name:=, =#+caption:=) go with the element they precede.
NEW-BODY is a string; empty clears those body elements.
Returns (:id :file). Errors loudly on unknown ID or malformed file."
  (sns-roam--update-section
   id
   (lambda (section)
     (sns-roam--map-children
      (lambda (children)
        (append (seq-filter #'sns-roam--section-header-p children)
                (sns-roam--parse-body-elements new-body)))
      section))))

(defun sns-roam-append-link (from-id to-id label before after)
  "Append a relationship paragraph to FROM-ID linking to TO-ID.
The paragraph reads BEFORE then an inline [[id:TO-ID][LABEL]] link
then AFTER, and becomes the last body element. Existing content is
untouched. One-directional; org-roam backlinks give the reverse.
The primitive does NOT dedupe — call it once per intended link.
Loud failure if FROM-ID or TO-ID is unknown. Returns (:from :to :file)."
  (sns-roam--node-file-or-error to-id)  ; validate target exists, loud
  (let* ((link  (org-ml-build-link (concat "id:" to-id) label))
         ;; Drop empty BEFORE/AFTER so no empty secondary-strings sneak in.
         (parts (seq-remove (lambda (x) (and (stringp x) (string-empty-p x)))
                            (list before link after)))
         (res (sns-roam--update-section
              from-id
              (lambda (section)
                (sns-roam--map-children
                 (lambda (children)
                   (append children
                           (list (apply #'org-ml-build-paragraph parts))))
                 section)))))
    (list :from from-id :to to-id :file (plist-get res :file))))

(defun sns-roam-body-elements (id)
  "Return the body elements before the first heading of roam node ID.

Returns:
  (:id ID :file FILE :elements NODES)

NODES are the parsed org-ml children of the note's first section,
without the property drawer and `#+' keywords, in buffer order; nil
when there is no such body.  The note is parsed from the buffer
`find-file-noselect' returns, the one `sns-roam--update-section'
edits, so unsaved edits are included.  Writes nothing.  Errors
loudly on an unknown ID."
  (let ((file (sns-roam--node-file-or-error id)))
    (with-current-buffer (find-file-noselect file)
      (let ((first-child (car (org-ml-get-children
                               (org-ml-parse-this-buffer)))))
        (list :id       id
              :file     file
              :elements (when (org-ml-is-type 'section first-child)
                          (seq-remove #'sns-roam--section-header-p
                                      (org-ml-get-children first-child))))))))

(defun sns-roam-replace-element (id pred new-element)
  "Replace the unique body element of node ID matching PRED with NEW-ELEMENT.
PRED is a unary predicate on an org-ml node; NEW-ELEMENT is a built
org-ml node. Asserts exactly one match — loud error on zero or many,
so an ambiguous edit never silently hits the wrong element. Composes
through `sns-roam--update-section'. Returns (:id :file)."
  (sns-roam--update-section
   id
   (lambda (section)
     (let ((matches (org-ml-match `((:pred ,pred)) section)))
       (unless (= 1 (length matches))
         (error "sns-roam: replace-element matched %d elements, need exactly 1"
                (length matches)))
       (org-ml-match-map `((:pred ,pred))
                         (lambda (_old) new-element)
                         section)))))

(defun sns-roam--insert-beside (children anchor new-element after)
  "Return CHILDREN with NEW-ELEMENT next to ANCHOR, a member of CHILDREN.
AFTER non-nil places it after ANCHOR, nil before.  The child in
front of NEW-ELEMENT keeps its post-blank, raised to at least 1,
unless it is header furniture, which is left as it was.  NEW-ELEMENT
gets post-blank 1 when a child follows it, and otherwise the
post-blank ANCHOR had.  Every other child is returned as it was.
Pure."
  (let ((at-least-one (lambda (node)
                        (org-ml-set-property
                         :post-blank
                         (max 1 (org-ml-get-property :post-blank node))
                         node))))
    (cl-mapcan
     (lambda (child next)
       (cond
        ((and (eq child anchor) after)
         (list (funcall at-least-one child)
               (org-ml-set-property
                :post-blank
                (if next 1 (org-ml-get-property :post-blank anchor))
                new-element)))
        ((eq child anchor)
         (list (org-ml-set-property :post-blank 1 new-element) child))
        ((and (eq next anchor) (not after)
              (not (sns-roam--section-header-p child)))
         (list (funcall at-least-one child)))
        (t (list child))))
     children
     (append (cdr children) (list nil)))))

(defun sns-roam--body-signature (children)
  "Return the type and trimmed text of each body element in CHILDREN."
  (mapcar (lambda (element)
            (list (org-ml-get-type element)
                  (org-ml-to-trimmed-string element)))
          (seq-remove #'sns-roam--section-header-p children)))

(defun sns-roam--check-reparse (section)
  "Return SECTION if its printed text parses back to the same body.
Compares the body elements of SECTION with those org reads from
`org-ml-to-string' of SECTION, by type and trimmed text.  Raises an
`sns-roam:' error on a mismatch, such as two elements merged by too
few blank lines.  Pure."
  (let ((planned  (sns-roam--body-signature (org-ml-get-children section)))
        (reparsed (sns-roam--body-signature
                   (sns-roam--parse-body-elements (org-ml-to-string section)))))
    (unless (equal planned reparsed)
      (error "sns-roam: insert-element planned %d body elements but they read back as %d"
             (length planned) (length reparsed)))
    section))

(defun sns-roam--insert-into-section (section pred new-element after)
  "Return SECTION with paragraph NEW-ELEMENT beside the body element matching PRED.
PRED sees only body elements, never the property drawer or `#+'
keywords, and must match exactly one.  AFTER non-nil places
NEW-ELEMENT after the match, nil before.  Raises an `sns-roam:' error
when NEW-ELEMENT is not a paragraph, when PRED matches zero or many
elements, or when the result would not read back as planned.  Pure."
  (unless (org-ml-is-type 'paragraph new-element)
    (error "sns-roam: insert-element takes a paragraph, not a %s"
           (org-ml-get-type new-element)))
  (let ((matches (seq-filter
                  (lambda (child)
                    (and (not (sns-roam--section-header-p child))
                         (funcall pred child)))
                  (org-ml-get-children section))))
    (unless (= 1 (length matches))
      (error "sns-roam: insert-element matched %d elements, need exactly 1"
             (length matches)))
    (sns-roam--check-reparse
     (sns-roam--map-children
      (lambda (children)
        (sns-roam--insert-beside children (car matches) new-element after))
      section))))

(defun sns-roam-insert-element (id pred new-element &optional after)
  "Insert paragraph NEW-ELEMENT beside the body element of node ID matching PRED.
PRED is a unary predicate on an org-ml node and sees only body
elements, never the property drawer or `#+' keywords.  NEW-ELEMENT
is a paragraph built with `org-ml-build-paragraph'.  AFTER non-nil
inserts after the match, nil before it.  No blank-line gap shrinks,
and every other element keeps its text.  Errors loudly, leaving the
file unchanged, when NEW-ELEMENT is not a paragraph, PRED matches
zero or many elements, the result would not read back as planned,
or ID is unknown.  Composes through `sns-roam--update-section'.
Returns (:id :file)."
  (sns-roam--update-section
   id
   (lambda (section)
     (sns-roam--insert-into-section section pred new-element after))))

(defun sns-roam--upsert-keyword (section key value)
  "Return SECTION with KEY's keyword set to VALUE.
Replaces existing keyword in place; appends if absent."
  (let* ((children (org-ml-get-children section))
         (found    nil)
         (updated  (mapcar
                    (lambda (c)
                      (if (and (org-ml-is-type 'keyword c)
                               (string= (org-ml-get-property :key c) key))
                          (progn
                            (setq found t)
                            (org-ml-set-property :value value c))
                        c))
                    children)))
    (org-ml-set-children
     (if found
         updated
       (append updated (list (org-ml-build-keyword key value))))
     section)))

(defun sns-roam-set-keyword (id key value)
  "Set #+KEY: VALUE in the top-level section of roam node ID.

KEY is the bare uppercase keyword name (e.g. \"TITLE\"); VALUE
is a string. Returns t on success. Errors loudly on unknown ID
or missing top-level section."
  (let ((file (sns-roam--node-file-or-error id)))
    (with-current-buffer (find-file-noselect file)
      (let* ((tree    (org-ml-parse-this-buffer))
             (section (car (org-ml-get-children tree))))
        (unless (and section (org-ml-is-type 'section section))
          (error "sns-roam: %s has no top-level section" file))
        (let* ((new-section (sns-roam--upsert-keyword section key value))
               (new-tree    (org-ml-set-children
                             (cons new-section
                                   (cdr (org-ml-get-children tree)))
                             tree)))
          (erase-buffer)
          (insert (org-ml-to-string new-tree))
          (save-buffer)
          t)))))

(defun sns-roam--split-roam-filename (path)
  "Return (PREFIX . SLUG) from a roam filename PATH.
PREFIX is the 14-digit timestamp + dash; SLUG is the body
between dash and =.org=. Errors if PATH doesn't match the
expected shape."
  (let ((name (file-name-nondirectory path)))
    (unless (string-match "^\\([0-9]\\{14\\}-\\)\\(.+\\)\\.org$" name)
      (error "sns-roam: %s does not match roam filename shape" name))
    (cons (match-string 1 name) (match-string 2 name))))

(defun sns-roam-rename-file (id new-slug)
  "Rename roam node ID's file to use NEW-SLUG, preserving the timestamp prefix.

Returns the new absolute path. Errors if ID is unknown, the
filename doesn't match the expected =TIMESTAMP-SLUG.org= shape,
or the destination already exists."
  (let* ((old-path (sns-roam--node-file-or-error id))
         (dir      (file-name-directory old-path))
         (parts    (sns-roam--split-roam-filename old-path))
         (prefix   (car parts))
         (new-name (concat prefix new-slug ".org"))
         (new-path (expand-file-name new-name dir)))
    (when (file-exists-p new-path)
      (error "sns-roam: refusing to overwrite existing file %s" new-path))
    (when (string= old-path new-path)
      (error "sns-roam: new slug %S produces the same filename" new-slug))
    (let ((buf (find-buffer-visiting old-path)))
      (rename-file old-path new-path)
      (when buf
        (with-current-buffer buf
          (set-visited-file-name new-path nil t))))
    new-path))

(defun sns-roam-rename (id new-title)
  "Rewrite roam node ID's title to NEW-TITLE and rename its file to match.

Slug derivation uses `org-roam-node-slug' for parity with the
capture template. Returns a plist (:id :title :file)."
  (sns-roam-set-keyword id "TITLE" new-title)
  (let* ((node    (org-roam-node-from-id id))
         (_       (unless node
                    (error "sns-roam: node %S vanished after title rewrite" id)))
         (slug    (org-roam-node-slug node))
         (new-path (sns-roam-rename-file id slug)))
    (list :id id :title new-title :file new-path)))

(defun sns-roam--org-timestamp-of (time)
  "Return TIME as an inactive Org timestamp string,
matching the capture template's =%U= output (e.g. \"[2026-05-31 Sun 09:14]\").
TIME is an emacs internal time value (as produced by
`current-time', `encode-time', `parse-iso8601-time-string', etc.)."
  (format-time-string "[%Y-%m-%d %a %H:%M]" time))

(defun sns-roam--filename-prefix-of (time)
  "Return TIME as a 14-digit YYYYMMDDhhmmss filename prefix.
TIME is an emacs internal time value."
  (format-time-string "%Y%m%d%H%M%S" time))

(defun sns-roam--build-header-properties (id created kind aliases)
  "Return the list of =node-property= elements for a roam header.
ALIASES is a list of strings; when non-empty an extra
=ROAM_ALIASES= property is appended."
  (let ((base (list (org-ml-build-node-property "ID" id)
                    (org-ml-build-node-property "CREATED" created)
                    (org-ml-build-node-property "KIND" kind))))
    (if aliases
        (append base
                (list (org-ml-build-node-property
                       "ROAM_ALIASES"
                       (mapconcat (lambda (a) (format "\"%s\"" a))
                                  aliases " "))))
      base)))

(defun sns-roam--registered-file (id)
  "Return the file the org-roam database holds for node ID, or nil.
Resolves through `org-roam-node-from-id', as the edit primitives do."
  (let ((node (org-roam-node-from-id id)))
    (when node
      (org-roam-node-file node))))

(defun sns-roam--separate-body-elements (elements)
  "Return ELEMENTS with a blank line after each one but the last.
`org-ml-build-paragraph' gives a paragraph a :post-blank of 0, so
built paragraphs written in a row share no blank line and org reads
them as one paragraph. An element that already asks for more blank
lines keeps them. The last element is left alone, so no blank line
appears before the first headline, as `sns-roam-set-body' writes it."
  (append (mapcar (lambda (element)
                    (org-ml-set-property
                     :post-blank
                     (max 1 (org-ml-get-property :post-blank element))
                     element))
                  (butlast elements))
          (last elements)))

(defun sns-roam-create-node (title kind &optional elements id aliases created-time slug-source)
  "Create a new roam node with TITLE and KIND, returning a plist.

Slugifies TITLE for the filename, writes the file under
`org-roam-directory' with the standard roam header (:ID,
:CREATED, :KIND, optional :ROAM_ALIASES:, #+title) followed by
ELEMENTS — a list of org-ml AST nodes forming the body. ID, if
nil, is freshly generated via `org-id-new'. ALIASES is an
optional list of strings; when non-empty written as
:ROAM_ALIASES: per org-roam convention. CREATED-TIME, if
non-nil, is an emacs internal time value used in place of
`current-time' for both the :CREATED: property and the
filename's 14-digit prefix; both outputs are formatted from the
same time value. SLUG-SOURCE, if non-nil, is slugified for the
filename in place of TITLE — use it to decouple the filename slug
from a title that carries extra detail (e.g. an appended date),
so the file stays cleanly named while the title remains human.
Indexes the new file in the org-roam database, so the edit
primitives can resolve the returned ID at once.
Returns (:id :title :file). Errors before writing anything if the
destination exists or the database holds ID for another file.
Errors after indexing if ID does not resolve to the new file."
  (let* ((id       (or id (org-id-new)))
         (slug     (org-roam-node-slugify (or slug-source title)))
         (prefix   (sns-roam--filename-prefix-of created-time))
         (filename (concat prefix "-" slug ".org"))
         (path     (expand-file-name filename org-roam-directory))
         (created  (sns-roam--org-timestamp-of created-time))
         (props    (sns-roam--build-header-properties id created kind aliases))
         (drawer   (apply #'org-ml-build-property-drawer props))
         (kw       (org-ml-build-keyword "title" title))
         ;; Split ELEMENTS into the leading paragraph-ish section
         ;; children (which co-exist with drawer + keyword in a single
         ;; section) and the trailing headlines (which sit as siblings).
         (split-pos (or (cl-position-if
                         (lambda (e) (eq (org-ml-get-type e) 'headline))
                         elements)
                        (length elements)))
         (section-children (sns-roam--separate-body-elements
                            (cl-subseq elements 0 split-pos)))
         (sibling-headlines (cl-subseq elements split-pos))
         (section  (apply #'org-ml-build-section
                          (append (list drawer kw) section-children)))
         (content  (mapconcat #'org-ml-to-string
                              (cons section sibling-headlines)
                              "")))
    (when (file-exists-p path)
      (error "sns-roam: refusing to overwrite existing file %s" path))
    ;; org-roam only warns when it indexes a node whose ID another
    ;; file already holds, and the ID keeps resolving to that file.
    ;; Refuse before writing, so a retried batch that reuses a
    ;; pre-minted ID cannot leave a second file claiming it.
    (let ((registered (sns-roam--registered-file id)))
      (when registered
        (error "sns-roam: id %S already names %s, refusing to create %s"
               id registered path)))
    (with-temp-buffer
      (insert content)
      (write-region (point-min) (point-max) path nil 'silent))
    ;; The edit primitives look IDs up in the database, so a node
    ;; that is only on disk is unknown to them until it is indexed.
    (org-roam-db-update-file path)
    ;; Indexing reports some failures only as warnings, so check that
    ;; the ID now resolves to the new file before reporting success.
    (let ((registered (sns-roam--registered-file id)))
      (unless (and registered (file-equal-p registered path))
        (error "sns-roam: id %S resolves to %s after indexing, not to %s"
               id registered path)))
    (list :id id :title title :file path)))

(defun sns-roam--meeting-title (series time)
  "Return the title for a meeting-note instance of SERIES at TIME.
Appends an ISO date so instances are distinguishable in the
node-find picker while sharing a series name. Pure."
  (format "%s %s" series (format-time-string "%Y-%m-%d" time)))

(defun sns-roam-meeting-note (series)
  "Create a dated note instance for a recurring meeting SERIES.

SERIES is the stable series name (e.g. \"alan-smithee-1-1\",
\"pir-prep\", \"incident-review\"). The new node's title is
SERIES with today's date appended (\"alan-smithee-1-1 2026-06-16\")
so each occurrence is a distinct, picker-distinguishable node;
the filename slug derives from the bare SERIES, so the file is
not double-dated (org already supplies the timestamp prefix).
KIND is \"fleeting\" — raw meeting capture, to be mined into
permanent notes later. Always creates a fresh instance — never
finds an existing node — so identical series names never
collide. Opens the new file for editing.

Returns the create plist (:id :title :file)."
  (interactive
   (list (read-string "Recurring meeting series (e.g. alan-smithee-1-1): ")))
  (let* ((trimmed (string-trim series)))
    (when (string-empty-p trimmed)
      (error "sns-roam-meeting-note: empty series name"))
    (let* ((now    (current-time))
           (title  (sns-roam--meeting-title trimmed now))
           (result (sns-roam-create-node title "fleeting" nil nil nil now trimmed)))
      (find-file (plist-get result :file))
      result)))

(provide 'sns-roam-api)
;;; sns-roam-api.el ends here
