;;; python-django.el --- A Jazzy package for managing Django projects

;; Copyright (C) 2011 Free Software Foundation, Inc.

;; Author: Fabián E. Gallina <fabian@anue.biz>
;; URL: https://github.com/fgallina/python-django.el
;; Version: 0.1
;; Maintainer: FSF
;; Created: Jul 2011
;; Keywords: languages

;; This file is NOT part of GNU Emacs.

;; python-django.el is free software: you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version.

;; python-django.el is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with python-django.el.  If not, see
;; <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Django project management package with the goodies you would expect
;; and then some.  The project buffer workings is pretty much inspired
;; by the good ol' `magit-status' buffer.

;; This package relies heavily in fgallina's `python.el' available in
;; stock Emacs>=24.3 (or https://github.com/fgallina/python.el).

;; Implements File navigation (per app, STATIC_ROOT, MEDIA_ROOT and
;; TEMPLATE_DIRS), Etag building, Grep in project, Quick jump (to
;; settings, project root, virtualenv and docs), Management commands
;; and Quick management commands.

;; File navigation: After opening a project, a directory tree for each
;; installed app, the STATIC_ROOT, the MEDIA_ROOT and each
;; TEMPLATE_DIRS is created.  Several commands are provided to work
;; with the current directory at point.

;; Etags building: Provides a simple wrapper to create etags for
;; current opened project.

;; Grep in project: Provides a simple way to grep relevant project
;; directories using `rgrep'.  You can override the use of `rgrep' by
;; tweaking the `python-django-cmd-grep-function'.

;; Quick jump: fast key bindings to jump to the settings module, the
;; project root, the current virtualenv and Django official web docs
;; are provided.

;; Management commands: You can run any management command from the
;; project buffer via `python-django-mgmt-run-command' or via the
;; quick management commands accesible from the Django menu.
;; Completion is provided for all arguments and you can cycle through
;; opened management command process buffers very easily.  Another
;; cool feature is that comint processes are spiced up with special
;; processing, for instance if are using runserver and get a
;; breakpoint via pdb or ipdb the pdb-tracking provided by
;; `python-mode' will trigger or if you enter dbshell the proper
;; `sql-mode' will be used.

;; Quick management commands: This mode provides quick management
;; commands (management commands with sane defaults, smart prompt
;; completion and process extra processing) defined to work with the
;; most used Django built-in management commands like syncdb, shell,
;; runserver, test; several good ones from `django-extensions' like
;; shell_plus, clean_pyc; and `south' ones like convert_to_south,
;; migrate, schemamigration.  You can define new quick commands via
;; the `python-django-qmgmt-define' and define ways to handle when
;; it's finished by defining a callback function.

;;; Usage:

;; The main entry point is the `python-django-open-project'
;; interactive function, see its documentation for more info on its
;; behavior.  Mainly this function requires two things, a project path
;; and a settings module.  How you chose them really depends on your
;; project's directory layout.  The recommended way to chose your
;; project root, is to use the directory containing your settings
;; module; for instance if your settings module is in
;; /path/django/settings.py, use /path/django/ as your project path
;; and django.settings as your settings module.  Double check the
;; `python-django-python-executable' really matches yours.

;;; Installation:

;; Add this to your .emacs:

;; (add-to-list 'load-path "/folder/containing/file")
;; (require 'python-django)

;;; Code:

(require 'hippie-exp)
(require 'json)
(require 'python)
(require 'sql)
(require 'tree-widget)
(require 'widget)

(eval-when-compile
  (require 'cl)
  (require 'wid-edit)
  ;; Avoid compiler warnings
  (defvar view-return-to-alist))

(defgroup python-django nil
  "Python Django project goodies."
  :group 'convenience
  :version "24.2")


;;; keymaps

(defvar python-django-mode-map
  (let ((map (make-keymap)))
    (suppress-keymap map t)
    (define-key map [remap next-line] 'python-django-ui-widget-forward)
    (define-key map [remap previous-line] 'python-django-ui-widget-backward)
    (define-key map [remap forward-char] 'python-django-ui-widget-forward)
    (define-key map [remap backward-char] 'python-django-ui-widget-backward)
    (define-key map [remap beginning-of-buffer]
      'python-django-ui-beginning-of-widgets)
    (define-key map [remap newline] 'python-django-ui-safe-button-press)
    (define-key map [remap widget-forward] 'python-django-ui-safe-button-press)
    (define-key map [remap widget-backward] 'python-django-ui-safe-button-press)
    (define-key map (kbd "p") 'python-django-ui-widget-backward)
    (define-key map (kbd "n") 'python-django-ui-widget-forward)
    (define-key map (kbd "b") 'python-django-ui-widget-backward)
    (define-key map (kbd "f") 'python-django-ui-widget-forward)
    (define-key map (kbd "d") 'python-django-cmd-dired-at-point)
    (define-key map (kbd "w") 'python-django-cmd-directory-at-point)
    (define-key map (kbd "ja") 'python-django-cmd-jump-to-app)
    (define-key map (kbd "jm") 'python-django-cmd-jump-to-media)
    (define-key map (kbd "jt") 'python-django-cmd-jump-to-template-dir)
    (define-key map (kbd "vs") 'python-django-cmd-visit-settings)
    (define-key map (kbd "vr") 'python-django-cmd-visit-project-root)
    (define-key map (kbd "vv") 'python-django-cmd-visit-virtualenv)
    (define-key map (kbd "t") 'python-django-cmd-build-etags)
    (define-key map (kbd "s") 'python-django-cmd-grep)
    (define-key map (kbd "o") 'python-django-cmd-open-docs)
    (define-key map (kbd "h") 'python-django-help)
    (define-key map (kbd "m") 'python-django-mgmt-run-command)
    (define-key map (kbd "g") 'python-django-refresh-project)
    (define-key map (kbd "q") 'python-django-close-project)
    (define-key map (kbd "K") 'python-django-mgmt-kill-all)
    (define-key map (kbd "$")
      'python-django-ui-cycle-mgmt-opened-buffers-forward)
    (define-key map (kbd "#")
      'python-django-ui-cycle-mgmt-opened-buffers-backward)
    (easy-menu-define python-django-menu map "Python Django Mode menu"
      `("Django"
        :help "Django project tools"
        ["Run management command"
         python-django-mgmt-run-command
         :help "Run management command in current project"]
        ["Kill all running commands"
         python-django-mgmt-kill-all
         :help "Kill all running commands for current project"]
        ["Get command help" python-django-help
         :help "Get help for any project's management commands"]
        ["Cycle to next running management command"
         python-django-ui-cycle-mgmt-opened-buffers-forward
         :help "Cycle to next running management command"]
        ["Cycle to previous running management command"
         python-django-ui-cycle-mgmt-opened-buffers-backward
         :help "Cycle to previous running management command"]
        "--"
        ;; Reserved for quick management commands
        "---"
        ["Browse Django documentation"
         python-django-cmd-open-docs
         :help "Open a Browser with Django's documentation"]
        ["Build Tags"
         python-django-cmd-build-etags
         :help "Build TAGS file for python source in project"]
        ["Dired at point"
         python-django-cmd-dired-at-point
         :help "Open dired at current tree node"]
        ["Grep in project directories"
         python-django-cmd-grep
         :help "Grep in project directories"]
        ["Refresh project"
         python-django-refresh-project
         :help "Refresh project"]
        "--"
        ["Visit settings file"
         python-django-cmd-visit-settings
         :help "Visit settings file"]
        ["Visit virtualenv directory"
         python-django-cmd-visit-virtualenv
         :help "Visit virtualenv directory"]
        ["Visit project root directory"
         python-django-cmd-visit-project-root
         :help "Visit project root directory"]
        "--"
        ["Jump to app's directory"
         python-django-cmd-jump-to-app
         :help "Jump to app's directory"]
        ["Jump to a media directory"
         python-django-cmd-jump-to-media
         :help "Jump to a media directory"]
        ["Jump to a template directory"
         python-django-cmd-jump-to-template-dir
         :help "Jump to a template directory"]))
    map)
  "Keymap for `python-django-mode'.")


;;; Some utility variables

;;; XXX: This might be moved to python.el itself.
(defcustom python-django-python-executable "python"
  "Python executable used in project."
  :group 'python-django
  :type 'string)


;;; Faces

(defgroup python-django-faces nil
  "Customize the appearance of Django buffers."
  :prefix "python-django-"
  :group 'faces
  :group 'python-django)

(defface python-django-face-header
  '((t :inherit font-lock-function-name-face))
  "Face for generic header lines.

Many Django faces inherit from this one by default."
  :group 'python-django-faces)

(defface python-django-face-path
  '((t :inherit font-lock-type-face))
  "Face for paths."
  :group 'python-django-faces)

(defface python-django-face-title
  '((t :inherit font-lock-keyword-face))
  "Face for titles."
  :group 'python-django-faces)

(defface python-django-face-django-version
  '((t :inherit python-django-face-header))
  "Face for project's Django version."
  :group 'python-django-faces)

(defface python-django-face-project-root
  '((t :inherit python-django-face-path))
  "Face for project path."
  :group 'python-django-faces)

(defface python-django-face-settings-module
  '((t :inherit python-django-face-header))
  "Face for project settings module."
  :group 'python-django-faces)

(defface python-django-face-virtualenv-path
  '((t :inherit python-django-face-header))
  "Face for project settings module."
  :group 'python-django-faces)


;;; Dev tools

(font-lock-add-keywords
 'emacs-lisp-mode
 `(("(\\(python-django-qmgmt-define\\)\\>[ \t]\\([^ \t]+\\)"
    (1 'font-lock-keyword-face)
    (2 'font-lock-function-name-face))))


;;; Utility functions

(defun python-django-util-clone-local-variables ()
  "Clone local variables from manage.py file.
This function is intended to be used so the project buffer gets
the same variables of python files."
  (let* ((file-name
          (expand-file-name
           python-django-info-manage.py-path))
         (manage.py-exists (get-file-buffer file-name))
         (manage.py-buffer
          (or manage.py-exists
              (prog1
                  (find-file-noselect file-name t)
                (message nil)))))
    (python-util-clone-local-variables manage.py-buffer)
    (when (not manage.py-exists)
      (kill-buffer manage.py-buffer))))

(defmacro python-django-util-alist-add (key value alist)
  "Update for KEY the VALUE in ALIST."
  `(let* ((k (if (bufferp ,key)
                 (buffer-name ,key)
               ,key))
          (v (if (bufferp ,value)
                 (buffer-name ,value)
               ,value))
          (elt (assoc k ,alist)))
     (if (not elt)
         (setq ,alist (cons (list k v) ,alist))
       (and (not (member v (cdr elt)))
            (setf (cdr elt)
                  (cons v (cdr elt)))))))

(defmacro python-django-util-alist-del (key value alist)
  "Remove for KEY the VALUE in ALIST."
  `(let* ((k (if (bufferp ,key)
                 (buffer-name ,key)
               ,key))
          (v (if (bufferp ,value)
                 (buffer-name ,value)
               ,value))
          (elt (assoc k ,alist)))
     (and elt (setf (cdr elt) (remove v (cdr elt))))))

(defmacro python-django-util-alist-del-key (key alist)
  "Empty KEY in ALIST."
  `(let* ((k (if (bufferp ,key)
                 (buffer-name ,key)
               ,key))
          (elt (assoc k ,alist)))
     (and elt (setf (cdr elt) nil))))

(defun python-django-util-alist-get (key alist)
  "Get values for KEY in ALIST."
  (and (bufferp key) (setq key (buffer-name key)))
  (cdr (assoc key alist)))


;;; Help

(defun python-django--help-get (&optional command)
  "Get help for COMMAND."
  (let* ((process-environment
          (python-django-info-calculate-process-environment))
         (exec-path (python-shell-calculate-exec-path)))
    (shell-command-to-string
     (format "%s %s help%s"
             (executable-find python-django-python-executable)
             python-django-info-manage.py-path
             (or (and command (concat " " command)) "")))))

(defun python-django-help (&optional command show-help)
  "Get help for given COMMAND.
Optional argument SHOW-HELP when non-nil causes the help buffer to pop."
  (interactive
   (list
    (python-django-minibuffer-read-command)))
  (if (or show-help (called-interactively-p 'interactive))
      (with-help-window (help-buffer)
        (princ (python-django--help-get command)))
    (python-django--help-get command)))

(defun python-django-help-close ()
  "Close help window if visible."
  (let ((win (get-buffer-window (help-buffer))))
    (and win
         (delete-window win))))


;;; Project info

(defvar python-django-project-root nil
  "Django project root directory.")

(defvar python-django-info-manage.py-path nil
  "Django project manage.py path.")

(defvar python-django-settings-module nil
  "Django project settings module.")

(defvar python-django-info-project-name nil
  "Django project name.")

(defun python-django-info-calculate-process-environment ()
  "Calculate process environment given current Django project."
  (let* ((process-environment (python-shell-calculate-process-environment))
         (pythonpath (getenv "PYTHONPATH"))
         (project-pythonpath
          (mapconcat
           'identity
           (list (expand-file-name python-django-project-root)
                 (expand-file-name "../" python-django-project-root))
           path-separator)))
    (setenv "PYTHONPATH" (if (not pythonpath)
                             project-pythonpath
                           (format "%s%s%s"
                                   pythonpath
                                   path-separator
                                   project-pythonpath)))
    (setenv "DJANGO_SETTINGS_MODULE"
            python-django-settings-module)
    process-environment))

(defun python-django-info-find-manage.py (&optional dir)
  "Find manage.py script starting from DIR."
  (let ((dir (expand-file-name (or dir default-directory))))
    (if (not (directory-files dir nil "^manage\\.py$"))
        (and
         ;; Check dir is not directory root.
         (not (string-equal "/" dir))
         (not
          (and (memq system-type '(windows-nt ms-dos))
               (string-match "\\`[a-zA-Z]:[/\\]\\'" dir)))
          (python-django-info-find-manage.py
           (expand-file-name
            (file-name-as-directory "..") dir)))
      (expand-file-name "manage.py" dir))))

(defvar python-django-info-prefetched-settings
  '("INSTALLED_APPS" "DATABASES" "MEDIA_ROOT" "STATIC_ROOT" "TEMPLATE_DIRS"))

(defvar python-django-info--get-setting-cache nil
  "Alist with cached list of settings.")

(defvar python-django-info--get-version-cache nil
  "Alist with cached list of settings.")

(defun python-django-info-get-version (&optional force)
  "Get current Django version path.
Values retrieved by this function are cached so when FORCE is
non-nil the cached value is invalidated."
  (or
   (and (not force) python-django-info--get-version-cache))
  (setq
   python-django-info--get-version-cache
   (let* ((process-environment
           (python-django-info-calculate-process-environment))
          (exec-path (python-shell-calculate-exec-path)))
     (shell-command-to-string
      (format
       "%s -c \"%s\""
       python-shell-interpreter
       (concat
        "from __future__ import print_function;"
        "import django; print(django.get_version(), end='')"))))))

(defun python-django-info-get-settings (&optional force)
  "Prefretch most common used settings for project.
Values retrieved by this function are cached so when FORCE is
non-nil the cached value is invalidated."
  (let ((cached
         (mapcar
          #'(lambda (setting)
              (assq (intern setting)
                    python-django-info--get-setting-cache))
          python-django-info-prefetched-settings)))
    (if (and (not force)
             (catch 'exit
               (dolist (elt cached)
                 (when (null elt)
                   (throw 'exit nil)))
               t))
        cached
      (let* ((process-environment
              (python-django-info-calculate-process-environment))
             (exec-path (python-shell-calculate-exec-path))
             (value
              (json-read-from-string
               (shell-command-to-string
                (format "%s -c \"%s %s\""
                        (executable-find python-django-python-executable)
                        (concat "from __future__ import print_function;"
                                "from django.conf import settings;"
                                "from django.utils import simplejson;"
                                "import os.path;")
                        (concat
                         "print(simplejson.dumps("
                         "dict([(name, getattr(settings, name)) "
                         "for name in ("
                         (mapconcat
                          #'(lambda (str) (concat "'" str "'"))
                          python-django-info-prefetched-settings
                          ", ")
                         ")])), end='')"))))))
        (mapc
         (lambda (elt)
           (let ((cached-val
                  (assq (car elt) python-django-info--get-setting-cache)))
             (if cached-val
                 (setcdr cached-val (cdr elt))
               (setq python-django-info--get-setting-cache
                     (cons elt python-django-info--get-setting-cache)))))
         value)))))

(defun python-django-info-get-setting (setting &optional force)
  "Get SETTING value from django.conf.settings in JSON format.
Values retrieved by this function are cached so when FORCE is
non-nil the cached value is invalidated."
  (let ((cached
         (or (and
              (member setting python-django-info-prefetched-settings)
              (assq (intern setting) (python-django-info-get-settings force)))
             (assq (intern setting)
                   python-django-info--get-setting-cache))))
    (if (and (not force) cached)
        (cdr cached)
      (let* ((process-environment
              (python-django-info-calculate-process-environment))
             (exec-path (python-shell-calculate-exec-path))
             (value
              (json-read-from-string
               (shell-command-to-string
                (format
                 "%s -c \"%s %s %s %s\""
                 (executable-find python-django-python-executable)
                 "from __future__ import print_function;"
                 "from django.conf import settings;"
                 "from django.utils import simplejson;"
                 (format
                  (concat
                   "print(simplejson.dumps("
                   "getattr(settings, '%s', None)), end='')")
                  setting)))))
             (already-cached (assq (intern setting)
                                   python-django-info--get-setting-cache)))
        (if already-cached
            (setcdr already-cached value)
          (setq python-django-info--get-setting-cache
                (cons (cons (intern setting) value)
                      python-django-info--get-setting-cache)))
        value))))

(defvar python-django-info--get-app-paths-cache nil
  "Cached list of apps and paths.")

(defun python-django-info-get-app-paths (&optional force)
  "Get project paths path.
Values retrieved by this function are cached so when FORCE is
non-nil the cached value is invalidated."
  (if (or force (not python-django-info--get-app-paths-cache))
      (setq
       python-django-info--get-app-paths-cache
       (let* ((process-environment
               (python-django-info-calculate-process-environment))
              (exec-path (python-shell-calculate-exec-path)))
         (json-read-from-string
          (shell-command-to-string
           (format "%s -c \"%s %s\""
                   (executable-find python-django-python-executable)
                   (concat "from __future__ import print_function;"
                           "from django.conf import settings;"
                           "from django.utils import simplejson;"
                           "import os.path;")
                   (concat
                    "app_paths = {}\n"
                    "for app in settings.INSTALLED_APPS:\n"
                    "    mod = __import__(app)\n"
                    "    if '.' in app:\n"
                    "        for sub in app.split('.')[1:]:\n"
                    "            mod = getattr(mod, sub)\n"
                    "    app_paths[app] = os.path.dirname(mod.__file__)\n"
                    "print(simplejson.dumps(app_paths), end='')"))))))
    python-django-info--get-app-paths-cache))

(defun python-django-info-get-app-path (app &optional force)
  "Get APP's path.
Values retrieved by this function are cached so when FORCE is
non-nil the cached value is invalidated."
  (cdr (assq (intern app) (python-django-info-get-app-paths force))))

(defun python-django-info-module-path (module)
  "Get MODULE's path."
  (let* ((process-environment
          (python-django-info-calculate-process-environment))
         (exec-path (python-shell-calculate-exec-path)))
    (shell-command-to-string
     (format
      "%s -c \"%s %s %s\""
      python-shell-interpreter
      "from __future__ import print_function;"
      (format "import os.path; import %s;" module)
      (format "print(%s.__file__.replace('.pyc', '.py'), end='')" module)))))

(defun python-django-info-directory-basename (&optional dir)
  "Get innermost directory name for given DIR."
  (car (last (split-string dir "/" t))))


;;; Hippie expand completion

(defun python-django-minibuffer-try-complete-args (old)
  "Try to complete word as a management command argument.
The argument OLD has to be nil the first call of this function, and t
for subsequent calls (for further possible completions of the same
string).  It returns t if a new completion is found, nil otherwise."
  (save-excursion
    (unless old
      (he-init-string (he-dabbrev-beg) (point))
      (when (not (equal he-search-string ""))
        (setq he-expand-list
              (sort (all-completions
                     he-search-string
                     minibuffer-completion-table)
                    'string<))))
    (while (and he-expand-list
                (he-string-member (car he-expand-list) he-tried-table))
      (setq he-expand-list (cdr he-expand-list)))
    (if (null he-expand-list)
        (progn (if old (he-reset-string)) ())
      (progn
        (he-substitute-string (car he-expand-list))
        (setq he-tried-table (cons (car he-expand-list)
                                   (cdr he-tried-table)))
        t))))

(defun python-django-minibuffer-try-complete-filenames (old)
  "Try to complete filenames in command arguments.
The argument OLD has to be nil the first call of this function, and t
for subsequent calls (for further possible completions of the same
string).  It returns t if a new completion is found, nil otherwise."
  (if (not old)
      (progn
        (he-init-string (let ((max-point (point)))
                          (save-excursion
                            (goto-char (he-file-name-beg))
                            (re-search-forward "--?[a-z0-9_-]+=?" max-point t)
                            (point)))
                        (point))
        (let ((name-part (file-name-nondirectory he-search-string))
              (dir-part (expand-file-name (or (file-name-directory
                                               he-search-string) ""))))
          (if (not (he-string-member name-part he-tried-table))
              (setq he-tried-table (cons name-part he-tried-table)))
          (if (and (not (equal he-search-string ""))
                   (file-directory-p dir-part))
              (setq he-expand-list (sort (file-name-all-completions
                                          name-part
                                          dir-part)
                                         'string-lessp))
            (setq he-expand-list ())))))
  (while (and he-expand-list
              (he-string-member (car he-expand-list) he-tried-table))
    (setq he-expand-list (cdr he-expand-list)))
  (if (null he-expand-list)
      (progn
        (if old (he-reset-string))
        ())
    (let ((filename (he-concat-directory-file-name
                     (file-name-directory he-search-string)
                     (car he-expand-list))))
      (he-substitute-string filename)
      (setq he-tried-table (cons (car he-expand-list) (cdr he-tried-table)))
      (setq he-expand-list (cdr he-expand-list))
      t)))


;;; Minibuffer

(defvar python-django-minibuffer-complete-command-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map minibuffer-local-must-match-map)
    map)
  "Keymap used for completing commands in minibuffer.")

(defvar python-django-minibuffer-complete-command-args-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map minibuffer-local-map)
    (define-key map "\t" 'hippie-expand)
    (define-key map [remap scroll-other-window]
      'python-django-minibuffer-scroll-help-window)
    (define-key map [remap scroll-other-window-down]
      'python-django-minibuffer-scroll-help-window-down)
    map)
  "Keymap used for completing command args in minibuffer.")

(defun python-django-minibuffer-read-command (&optional trigger-help)
  "Read django management command from minibuffer.
Optional argument TRIGGER-HELP sets if help buffer with commmand
details should be displayed."
  (let* ((current-buffer (current-buffer))
         (command
          (minibuffer-with-setup-hook
              (lambda ()
                (python-util-clone-local-variables current-buffer)
                (setq minibuffer-completion-table
                      (python-django-mgmt-list-commands)))
            (read-from-minibuffer
             "./manage.py: " nil
             python-django-minibuffer-complete-command-map))))
    (when trigger-help
      (python-django-help command t))
    command))

(defun python-django-minibuffer-read-command-args (command)
  "Read django management arguments for command from minibuffer.
Arguments are parsed for especific COMMAND."
  (let* ((current-buffer (current-buffer)))
    (minibuffer-with-setup-hook
        (lambda ()
          (python-util-clone-local-variables current-buffer)
          (setq minibuffer-completion-table
                (python-django-mgmt-list-command-args command))
          (set (make-local-variable 'hippie-expand-try-functions-list)
               '(python-django-minibuffer-try-complete-args
                 python-django-minibuffer-try-complete-filenames)))
      (read-from-minibuffer
       (format "./manage.py %s (args): " command)
       nil python-django-minibuffer-complete-command-args-map))))

(defun python-django-minibuffer-read-list (thing &rest args)
  "Helper function to read list of THING from minibuffer.
Optional argument ARGS are the args passed to the THING."
  (let ((objs))
    (catch 'exit
      (while t
        (add-to-list
         'objs
         (apply thing args) t)
        (when (not (y-or-n-p "Add another? "))
          (throw 'exit (mapconcat 'identity objs " ")))))))

(defun python-django-minibuffer-read-file-name (prompt)
  "Read a single file name from minibuffer.
PROMPT is a string to prompt user for filenames."
  (let ((use-dialog-box nil))
    ;; Lets make shell expansion work.
    (replace-regexp-in-string
     "[\\]\\*" "*"
     (shell-quote-argument
      (let ((func
             (if ido-mode
                 'ido-read-file-name
               'read-file-name)))
        (funcall func prompt python-django-project-root
                 python-django-project-root nil))))))

(defun python-django-minibuffer-read-file-names (prompt)
  "Read a list of file names from minibuffer.
PROMPT is a string to prompt user for filenames."
  (python-django-minibuffer-read-list
   'python-django-minibuffer-read-file-name prompt))

(defun python-django-minibuffer-read-app (prompt &optional initial-input full)
  "Read django app from minibuffer.
PROMPT is a string to prompt user for app.  Optional argument
INITIAL-INPUT is the initial prompted value.  When FULL is
non-nill the full module name for the installed app is prompted."
  (let ((apps (mapcar (lambda (app)
                        (if (not full)
                            (car (last (split-string app "\\.")))
                          app))
                      (python-django-info-get-setting "INSTALLED_APPS")))
        (current-buffer (current-buffer)))
    (minibuffer-with-setup-hook
        (lambda ()
          (python-util-clone-local-variables current-buffer)
          (setq minibuffer-completion-table apps))
      (catch 'app
        (while t
          (let ((app (read-from-minibuffer
                      prompt initial-input minibuffer-local-must-match-map)))
            (when (> (length app) 0)
              (throw 'app app))))))))

(defun python-django-minibuffer-read-apps (prompt &optional initial-input full)
  "Read django apps from minibuffer.
PROMPT is a string to prompt user for app.  Optional argument
INITIAL-INPUT is the initial prompted value.  When FULL is
non-nill the full module name for the installed app is prompted."
  (python-django-minibuffer-read-list
   'python-django-minibuffer-read-app prompt full))

(defun python-django-minibuffer-read-database (prompt &optional initial-input)
  "Read django database router name from minibuffer.
PROMPT is a string to prompt user for database.
Optional argument INITIAL-INPUT is the initial prompted value."
  (let ((databases (mapcar (lambda (router)
                             (format "%s" (car router)))
                           (python-django-info-get-setting "DATABASES")))
        (current-buffer (current-buffer)))
    (minibuffer-with-setup-hook
        (lambda ()
          (python-util-clone-local-variables current-buffer)
          (setq minibuffer-completion-table databases))
      (catch 'db
      (while t
        (let ((db (read-from-minibuffer
                   prompt initial-input minibuffer-local-must-match-map)))
          (when (> (length db) 0)
            (throw 'db db))))))))

(defun python-django-minibuffer-read-migration (prompt app)
  "Read south migration number for given app from minibuffer.
PROMPT is a string to prompt user for database.  APP is the app
to read migrations from."
  (let* ((migrations-dir (expand-file-name
                          "migrations"
                          (python-django-info-get-app-path app)))
         (migrations
          (mapcar (lambda (file)
                    file)
                  (directory-files migrations-dir
                                   nil "^[0-9]\\{4\\}_.*\\.py$"))))
    (minibuffer-with-setup-hook
        (lambda ()
          (setq minibuffer-completion-table migrations))
      (let ((migration (read-from-minibuffer
                        prompt nil minibuffer-local-must-match-map)))
        (when (not (string= migration ""))
          (substring migration 0 4))))))

(defun python-django-minibuffer-read-from-list (prompt lst &optional default)
  "Read a value from a list from minibuffer.
PROMPT is a string to prompt user.  LST is the list containing
the values to choose from.  Optional argument DEFAULT is the
default value."
  (minibuffer-with-setup-hook
      (lambda ()
        (setq minibuffer-completion-table lst))
    (read-from-minibuffer prompt default minibuffer-local-must-match-map)))


;;; Management commands

(defvar python-django-mgmt--available-commands nil
  "Alist with cached list of management commands for each project.")

(defun python-django-mgmt-list-commands (&optional force)
  "List available management commands.
Optional argument FORCE makes the function to recalculate the
list of command for current project instead of getting it from
the `python-django-mgmt--available-commands' cache."
  (and force
       (set (make-local-variable 'python-django-mgmt--available-commands) nil))
  (cdr
   (or python-django-mgmt--available-commands
       (let ((help-string (python-django-help)))
         (set (make-local-variable 'python-django-mgmt--available-commands)
              (let ((help-string (python-django-help))
                    (commands))
                (with-temp-buffer
                  (insert help-string)
                  (goto-char (point-min))
                  (delete-region
                   (and (re-search-forward "Usage: manage.py")
                        (line-beginning-position))
                   (or (and
                        (re-search-forward "Available subcommands:\n" nil t)
                        (forward-line -1)
                        (line-beginning-position))
                       (point-max)))
                  (goto-char (point-min))
                  (re-search-forward "Available subcommands:\n")
                  (while (re-search-forward " +\\([a-z0-9_]+\\)\n" nil t)
                    (setq commands
                          (cons (match-string-no-properties 1) commands)))
                  (reverse commands))))))))

(defun python-django-mgmt-list-command-args (command)
  "List available arguments for COMMAND."
  (let ((help-string (python-django-help command))
        (args))
    (with-temp-buffer
      (insert help-string)
      (goto-char (point-min))
      (when (re-search-forward "^Options:\n" nil t)
        (while (re-search-forward "--[a-z0-9_-]+=?" nil t)
          (setq args (cons (match-string 0) args))
          (append args (match-string 0)))
        (sort args 'string<)))))

(defun python-django-mgmt-make-comint (command process-name)
  "Run COMMAND with PROCESS-NAME in generic Comint buffer."
  (apply 'make-comint process-name
         python-shell-interpreter nil
         (split-string-and-unquote command)))

(defun python-django-mgmt-make-comint-for-shell (command process-name)
  "Run COMMAND with PROCESS-NAME in generic Comint buffer."
  (let ((python-shell-interpreter-args command))
    (python-shell-make-comint (python-shell-parse-command) process-name)))

(defun python-django-mgmt-make-comint-for-shell_plus (command process-name)
  "Run COMMAND with PROCESS-NAME in generic Comint buffer."
  (python-django-mgmt-make-comint-for-shell command process-name))

(defun python-django-mgmt-make-comint-for-runserver (command process-name)
  "Run COMMAND with PROCESS-NAME in generic Comint buffer."
  (python-django-mgmt-make-comint-for-shell command process-name))

(defun python-django-mgmt-make-comint-for-runserver_plus (command process-name)
  "Run COMMAND with PROCESS-NAME in generic Comint buffer."
  (python-django-mgmt-make-comint-for-runserver command process-name))

(defun python-django-mgmt-make-comint-for-dbshell (command process-name)
  "Run COMMAND with PROCESS-NAME in generic Comint buffer."
  (let* ((dbsetting (python-django-info-get-setting "DATABASES"))
         (dbengine (cdr (assoc 'ENGINE (assoc 'default dbsetting))))
         (sql-interactive-product-1
          (cond ((string= dbengine "django.db.backends.mysql")
                 'mysql)
                ((string= dbengine "django.db.backends.oracle")
                 'oracle)
                ((string= dbengine "django.db.backends.postgresql")
                 'postgres)
                ((string= dbengine "django.db.backends.sqlite3")
                 'sqlite)
                (t nil)))
         (buffer
          (python-django-mgmt-make-comint command process-name)))
    (with-current-buffer buffer
      (setq sql-buffer (current-buffer)
            sql-interactive-product sql-interactive-product-1)
      (sql-interactive-mode))
    buffer))

(defcustom python-django-mgmt-buffer-switch-function 'display-buffer
  "Function for switching to the process buffer.
The function receives one argument, the management command
process buffer."
  :group 'python-django
  :type '(radio (function-item switch-to-buffer)
                (function-item pop-to-buffer)
                (function-item display-buffer)
                (function :tag "Other")))

(defvar python-django-mgmt-output-buffer ""
  "Output buffer for the current management command.")

(defun python-django-mgmt-capture-output (output)
  "Accumulate command OUTPUT in `python-django-mgmt-output-buffer'.
This function is automatically added to
`comint-output-filter-functions' when
`python-django-mgmt-run-command' is told to capture output."
  (setq python-django-mgmt-output-buffer
        (concat python-django-mgmt-output-buffer
                (ansi-color-filter-apply output)))
  output)

(defvar python-django-mgmt--previous-window-configuration nil
  "Snapshot of previous window configuration before executing command.
This variable is for internal purposes, don't use it directly.")

(defun python-django-mgmt-restore-window-configuration ()
  "Restore window configuration after running a management command."
  (and python-django-mgmt--previous-window-configuration
       (set-window-configuration
        python-django-mgmt--previous-window-configuration)))

(defvar python-django-mgmt-parent-buffer nil
  "Parent project buffer for current process.")

(defvar python-django-mgmt--opened-buffers nil
  "Alist of currently opened process buffers.")

(defun python-django-mgmt-opened-buffers-for (parent-buffer)
  "Return all opened buffer names for PARENT-BUFFER."
  (python-django-util-alist-get
   parent-buffer python-django-mgmt--opened-buffers))

(defun python-django-mgmt-run-command (command
                                       &optional args capture-ouput no-pop)
  "Run management COMMAND with given ARGS.
When optional argument CAPTURE-OUPUT is non-nil process output is
captured in the variable `python-django-mgmt-output-buffer'.  If
optional argument NO-POP is provided the process buffer is not
displayed automatically."
  (interactive
     (list
      (setq command
            (python-django-minibuffer-read-command t))
      (python-django-minibuffer-read-command-args command)))
  (python-django-help-close)
  (when (not (member command (python-django-mgmt-list-commands)))
    (error
     "Management command %s is not available in current project" command))
  (let* ((args (or args ""))
         (process-environment
          (python-django-info-calculate-process-environment))
         (exec-path (python-shell-calculate-exec-path))
         (process-name (format "[Django %s] ./manage.py %s %s"
                               python-django-info-project-name
                               command args))
         (buffer-name (format "*%s*" process-name))
         (current-buffer (current-buffer))
         (make-comint-special-func-name
          (intern
           (format "python-django-mgmt-make-comint-for-%s" command)))
         (full-command
          (format "%s %s %s"
                  python-django-info-manage.py-path
                  command args))
         (buffer (get-buffer-create buffer-name)))
    (with-current-buffer buffer
      (python-util-clone-local-variables current-buffer)
      (set (make-local-variable 'python-django-mgmt-output-buffer) "")
      (and capture-ouput
           (add-hook (make-local-variable 'comint-output-filter-functions)
                     'python-django-mgmt-capture-output))
      (if (not (fboundp make-comint-special-func-name))
          (python-django-mgmt-make-comint full-command process-name)
        (funcall make-comint-special-func-name full-command process-name))
      (set (make-local-variable
            'python-django-mgmt-parent-buffer) current-buffer)
      (python-django-util-alist-add
       current-buffer (current-buffer)
       python-django-mgmt--opened-buffers)
      (add-hook
       'kill-buffer-hook
       (lambda ()
         (python-django-util-alist-del
          python-django-mgmt-parent-buffer (current-buffer)
          python-django-mgmt--opened-buffers))
       nil t))
    (unless no-pop
      (funcall python-django-mgmt-buffer-switch-function buffer-name))
    buffer))

(add-to-list 'debug-ignored-errors
             "^Management command .* is not available in current project.")

(defun python-django-mgmt-kill-all (&optional confirm command)
  "Kill all running commands for current project after CONFIRM.
When called with universal argument you can filter the COMMAND to kill."
  (interactive
   (list
    (y-or-n-p
     (format "Do you want to kill all running commands for %s? "
             python-django-info-project-name))
    (and current-prefix-arg
         (python-django-minibuffer-read-command nil))))
  (when confirm
    (dolist (buffer
             (python-django-mgmt-opened-buffers-for (current-buffer)))
      (when (or (not command)
                (string-match
                 (format "\\./manage.py %s" (or command "")) buffer))
        (let ((win (get-buffer-window buffer 0))
              (proc (get-buffer-process buffer)))
          (when win
            (delete-window win))
          (when proc
            (set-process-query-on-exit-flag proc nil)))
        (kill-buffer buffer)))))


;;; Management shortcuts

(defvar python-django-qmgmt--menu-items nil
  "List of menu items for quick management commands.")
(setq python-django-qmgmt--menu-items nil)

(defmacro python-django-qmgmt-define (name doc-or-args &optional args)
  "Define a quick management command.
Argument NAME is a symbol and it is used to calculate the
management command this command will execute, so it should have
the form cmdname[-rest].  Argument DOC-OR-ARGS might be the
docstring for the defined command or the list of arguments, when
a docstring is supplied ARGS is used as the list of arguments
instead.

This is a full example that will define how to execute Django's
dumpdata for the current application quickly:

  (python-django-qmgmt-define dumpdata-app
    \"Run dumpdata for current application.\"
    (:submenu \"Database\" :switches \"--format=json\" :binding \"dda\"
     (database \"Database\" \"default\" \"--database=\")
     (app \"App\")))

When that's is evaled a command called
`python-django-qmgmt-dumpdata' is created and will react
depending on the arguments passed to this macro.

All commands defined by this macro, when called with `prefix-arg'
will ask the user for values instead of using defaults.

ARGS is a list with the form:
    (KEYWORD-ARGUMENTS ARGLIST)

KEYWORD-ARGUMENTS available are ':binding' ':switches' and
':submenu', all of them are optional and their effects are:

    + :binding, when defined, the new command is bound to the
    default prefix for quick management commands plus this value.

    + :capture-output, when defined, the command output is
    captured in the `python-django-mgmt-output-buffer' variable
    which is available in the callback.

    + :msg, when defined, commands that use the
    `python-django-qmgmt-kill-and-msg-callback' show this instead
    of the buffer contents.

    + :no-pop, when defined, causes the process buffer to not be
    displayed.

    + :submenu, when defined, the quick management command is
    added within that submenu tree.  If omitted the menu is added
    to the root.

    + :switches, when defined, the new command is executed with
    those switches.

ARGLIST is a list of the form (VARNAME PROMPT DEFAULT SWITCH
FORCE-ASK), you can add 0 or more ARGLISTs depending on the
number of parameters you need to pass to the management command.
The description for each element of the list are:

    + VARNAME must be a symbol that must not repeat in other ARGLIST.

    + PROMPT must be a string for the prompt that will be shown
    when user is asked for a value using `read-string' or it can
    be a expresion that will be used to read the value for
    VARNAME.  When you need to use the calculated value of
    DEFAULT in the provided expression you can just use that
    variable like this:

        (read-file-name \"Fixture: \" nil default)

    + DEFAULT is an expression to be executed in order to
    calculate the default value for VARNAME.  This is optional
    and in the case is not provided or returns nil after executed
    the user will be prompted to insert a value for VARNAME.

    + SWITCH is a string that represents the switch used to pass
    the VARNAME's value to Django's management command.

    + FORCE-ASK might be nil or non-nil, when is non-nil the user
    will be asked to insert a value for VARNAME even if a default
    value is available."
  (declare
   (indent defun))
  (let ((docstring (when (stringp doc-or-args)
                     doc-or-args))
        (args (if (stringp doc-or-args)
                  args
                doc-or-args)))
    (let* ((defun-name (intern (format "qmgmt-%s" name)))
           (full-name (intern (format "python-django-%s" defun-name)))
           (callback (intern (format "%s-callback" full-name)))
           (command (car (split-string (format "%s" name) "-")))
           (switches)
           (binding)
           (no-pop)
           (quick-submenu)
           (msg)
           (capture-output)
           (submenu '("Django"))
           (iargs (let ((margs (purecopy args))
                        (iargs))
                    (while margs
                      (cond ((equal (car margs) :binding)
                             (setq binding (cadr margs))
                             (setq margs (cddr margs)))
                            ((equal (car margs) :no-pop)
                             (setq no-pop (cadr margs))
                             (setq margs (cddr margs)))
                            ((equal (car margs) :switches)
                             (setq switches (cadr margs))
                             (setq margs (cddr margs)))
                            ((equal (car margs) :submenu)
                             (setq quick-submenu (cadr margs))
                             (setq margs (cddr margs)))
                            ((equal (car margs) :msg)
                             (setq msg (cadr margs))
                             (setq margs (cddr margs)))
                            ((equal (car margs) :capture-output)
                             (setq capture-output (cadr margs))
                             (setq margs (cddr margs)))
                            (t
                             (setq iargs (cons (car margs) iargs))
                             (setq margs (cdr margs)))))
                    (reverse iargs)))
           (keys (when binding
                   (format "c%s" binding)))
           (defargs (mapcar 'car iargs))
           (cmd-spec (concat
                      (format "./manage.py %s " command)
                      (when switches
                        (format "%s " switches))
                      (when defargs
                        (mapconcat
                         (lambda (arg)
                           (let* ((switch (nth 3 arg))
                                  (switch
                                   (cond
                                    ((eq (length switch) 0)
                                     "")
                                    ((eq ?= (car (last (append switch nil))))
                                     switch)
                                    (t (format "%s " switch))))
                                  (varname (symbol-name (nth 0 arg))))
                             (format "%s<%s>" switch varname)))
                         iargs
                         " "))))
           (interactive-code
            (mapcar (lambda (arg)
                      (let* ((default (nth 2 arg))
                             (switch (nth 3 arg))
                             (switch
                              (cond ((eq (length switch) 0)
                                     "")
                                    ((eq ?= (car (last (append switch nil))))
                                     switch)
                                    (t (format "%s " switch))))
                             (force-ask (nth 4 arg))
                             (read-func
                              (if (listp (nth 1 arg))
                                  (nth 1 arg)
                                `(read-string ,(nth 1 arg) default))))
                         `(concat
                           ,switch
                           (setq ,(car arg)
                                 (let ((default ,default))
                                   (if (or ,force-ask
                                           current-prefix-arg
                                           (not default))
                                       ,read-func
                                     default))))))
                    iargs))
           (item-docstring
            (if docstring
                (car (split-string docstring "\n"))
              (format
               "Run ./manage.py %s command quickly."
               (concat command (if switches
                                   (concat " " switches)
                                 "")))))
           (full-submenu (if (not quick-submenu)
                             submenu
                           (append submenu (list quick-submenu))))
           (full-docstring
            (format "%s\n\n%s\n\n%s"
                    cmd-spec
                    (or docstring item-docstring)
                    (concat
                     "This is an interactive command defined by "
                     "`python-django-qmgmt-define' macro.\n"
                     "Users can override any parameter with defaults by "
                     "calling this command with `prefix-arg' .\n\n"
                     "Bound to: \n\n"
                     (when keys
                       (format "  * Keybinding: %s\n" keys))
                     (format "  * Menu: %s\n\n"
                             (mapconcat 'identity full-submenu " -> "))
                     (when switches
                       (format "Default switches: \n\n  * %s\n\n" switches))
                     (when iargs
                       (format
                        "Arguments: \n\n%s"
                        (mapconcat
                         (lambda (arg)
                           (let* ((default (nth 2 arg))
                                  (switch (nth 3 arg))
                                  (switch
                                   (cond
                                    ((eq (length switch) 0)
                                     nil)
                                    ((eq ?= (car (last (append switch nil))))
                                     switch)
                                    (t (format "%s " switch))))
                                  (force-ask (nth 4 arg)))
                             (concat
                              (format "  * %s:\n"
                                      (upcase (symbol-name (car arg))))
                              (format "    + Switch: %s\n" switch)
                              (format "    + Defaults: %s\n"
                                      (prin1-to-string default))
                              (format "    + Read SPEC: %s\n"
                                      (prin1-to-string (nth 1 arg)))
                              (format "    + Force prompt: %s\n"
                                      force-ask)
                              (format "    + Requires user interaction?: %s"
                                      (not (not (or force-ask default)))))))
                         iargs "\n\n")))))))
      `(progn
         (defun ,full-name ,defargs
           ,full-docstring
           (interactive
            (let ,defargs
              (list ,@interactive-code)))
           (setq python-django-mgmt--previous-window-configuration
                 (current-window-configuration))
           (let* ((has-callback (fboundp ',callback))
                  (process (get-buffer-process
                            (python-django-mgmt-run-command
                             ,command
                             (concat ,(or switches "") " "
                                     (mapconcat 'symbol-value ',defargs " "))
                             ,capture-output ,no-pop))))
             (when has-callback
               (lexical-let
                   ((cb
                     (apply-partially
                      ',callback
                      (cons
                       (cons :msg ,msg)
                       (mapcar
                        #'(lambda (sym)
                            (let ((val (symbol-value sym)))
                              (cons
                               sym
                               (cond
                                ((string-match "^--" val)
                                 (substring val (1+ (string-match "=" val))))
                                ((string-match "^-" val)
                                 (substring val 3))
                                (t val)))))
                        ',defargs)))))
                 (set-process-sentinel
                  process
                  #'(lambda (process status)
                      (when (string= status "finished\n")
                        (set-buffer (process-buffer process))
                        (funcall cb))))))))
         (when ,binding
           (ignore-errors
             (define-key python-django-mode-map ,keys ',full-name)))
         (when ,quick-submenu
           (add-to-list
            'python-django-qmgmt--menu-items
            '(easy-menu-add-item
              nil ',submenu (list ,quick-submenu) "---") t))
         (add-to-list
          'python-django-qmgmt--menu-items
          '(easy-menu-add-item
            nil ',full-submenu
            [,item-docstring
             ,full-name
             :help ,cmd-spec
             :active (member ,command (python-django-mgmt-list-commands))
             ] "---") t)
         ',full-name))))

(defun python-django-qmgmt-kill-and-msg-callback (args)
  "Callback for commands to be cleaned up on finish.
Argument ARGS is an alist with the arguments passed to the management command."
  (message (or (cdr (assq :msg args)) (buffer-string)))
  (kill-buffer)
  (python-django-mgmt-restore-window-configuration))

(defun python-django-qmgmt-add-menu-items ()
  "Add menu items for defined quick commands."
  (dolist (menu-item python-django-qmgmt--menu-items)
    ;; Some security checks
    (when (and (eq (car menu-item) 'easy-menu-add-item)
               (eq (cadr menu-item) nil)
               (listp (nth 2 menu-item))
               (or
                (vectorp (nth 3 menu-item))
                (listp (nth 3 menu-item))))
      (eval menu-item))))

(python-django-qmgmt-define collectstatic
  "Collect static files."
  (:submenu "Tools" :binding "ocs"))

(defalias 'python-django-qmgmt-collectstatic-callback
  'python-django-qmgmt-kill-and-msg-callback)

(python-django-qmgmt-define clean_pyc
  "Remove all python compiled files from the project."
  (:submenu "Tools" :binding "ocp" :no-pop t
   :msg "All *.pyc and *.pyo cleaned."))

(defalias 'python-django-qmgmt-clean_pyc-callback
  'python-django-qmgmt-kill-and-msg-callback)

(python-django-qmgmt-define create_command
  "Create management commands directory structure for app."
  (:submenu "Tools" :binding "occ" :no-pop t
   (app (python-django-minibuffer-read-app "App name: "))))

(defun python-django-qmgmt-create_command-callback (args)
  "Callback for create_command quick management command.
Optional argument ARGS args for it."
  (let* ((appname (cdr (assoc 'app args)))
         (manage-directory
          (file-name-directory
           (with-current-buffer
               python-django-mgmt-parent-buffer
             python-django-info-manage.py-path)))
         (default-app-dir
           (expand-file-name appname manage-directory))
         (default-create-dir
           (expand-file-name "management" default-app-dir))
         (delete-safe
          (and (file-exists-p default-app-dir)
               (equal (directory-files default-app-dir)
                      '("." ".." "management")))))
    (when (y-or-n-p
           (format "Created in app %s.  Move it? " default-app-dir))
      (let ((newdir
             (read-directory-name
              "Move app to: " manage-directory nil t)))
        (if (not (file-exists-p
                  (expand-file-name "management" newdir)))
            (rename-file default-create-dir newdir)
          (message
           "Directory structure already exists in %s" appname))
        (and delete-safe (delete-directory default-app-dir t)))))
  (kill-buffer)
  (python-django-mgmt-restore-window-configuration))

(python-django-qmgmt-define startapp
  "Create new Django app for current project."
  (:submenu "Tools" :binding "osa" :no-pop t
   (app "App name: ")))

(defun python-django-qmgmt-startapp-callback (args)
  "Callback for clean_pyc quick management command.
Optional argument ARGS args for it."
  (let ((appname (cdr (assoc 'app args)))
        (manage-directory
         (file-name-directory
          (with-current-buffer
              python-django-mgmt-parent-buffer
            python-django-info-manage.py-path))))
    (when (y-or-n-p
           (format
            "App created in %s.  Do you want to move it? "
            manage-directory))
      (rename-file
       (expand-file-name appname manage-directory)
       (read-directory-name
        "Move app to: " manage-directory nil t))))
  (kill-buffer)
  (python-django-mgmt-restore-window-configuration))

;; Shell

(python-django-qmgmt-define shell
  "Run a Python interpreter for this project."
  (:submenu "Shell" :binding "ss"))

(python-django-qmgmt-define shell_plus
  "Like the 'shell' but autoloads all models."
  (:submenu "Shell" :binding "sp"))

;; Database

(python-django-qmgmt-define syncdb
  "Sync database tables for all INSTALLED_APPS."
  (:submenu "Database" :binding "dsy" :no-pop t
   (database (python-django-minibuffer-read-database "Database: " default)
             "default" "--database=")))

(defalias 'python-django-qmgmt-syncdb-callback
  'python-django-qmgmt-kill-and-msg-callback)

(python-django-qmgmt-define dbshell
  "Run the command-line client for specified database."
  (:submenu "Database" :binding "dss"
   (database (python-django-minibuffer-read-database "Database: " default)
             "default" "--database=")))

(defvar python-django-qmgmt-dumpdata-formats '("json" "xml" "yaml")
  "Valid formats for dumpdata management command.")

(defcustom python-django-qmgmt-dumpdata-default-format "json"
  "Default format for quick dumpdata."
  :group 'python-django
  :type `(choice
          ,@(mapcar (lambda (fmt)
                      `(string :tag ,fmt ,fmt))
                    python-django-qmgmt-dumpdata-formats))
  :safe 'stringp)

(defcustom python-django-qmgmt-dumpdata-default-indent 4
  "Default indent value quick dumpdata."
  :group 'python-django
  :type 'integer
  :safe 'integerp)

(python-django-qmgmt-define dumpdata-all
  "Save the contents of the database as a fixture for all apps."
  (:submenu "Database" :binding "ddp" :no-pop t :capture-output t
   (database (python-django-minibuffer-read-database "Database: " default)
             "default" "--database=")
   (indent (number-to-string
            (read-number "Indent Level: "
                         (string-to-number default)))
           (number-to-string python-django-qmgmt-dumpdata-default-indent)
           "--indent=")
   (format (python-django-minibuffer-read-from-list
            "Dump to format: " python-django-qmgmt-dumpdata-formats default)
           "json" "--format=")))

(python-django-qmgmt-define dumpdata-app
  "Save the contents of the database as a fixture for the specified app."
  (:submenu "Database" :binding "dda" :no-pop t :capture-output t
   (database (python-django-minibuffer-read-database "Database: " default)
             "default" "--database=")
   (indent (number-to-string
            (read-number "Indent Level: "
                         (string-to-number default))) "4" "--indent=")
   (format (python-django-minibuffer-read-from-list
            "Dump to format: " python-django-qmgmt-dumpdata-formats default)
           "json" "--format=")
   (app (python-django-minibuffer-read-app "Dumpdata for App: "))))

(defun python-django-qmgmt-dumpdata-callback (args)
  "Callback executed after dumpdata finishes.
ARGS is an alist containing arguments passed to the quick
management command."
  (let ((file-name
         (catch 'file-name
           (while t
             (let ((file-name
                    (read-file-name
                     "Save fixture to file: "
                     (expand-file-name
                      (with-current-buffer
                          python-django-mgmt-parent-buffer
                        python-django-project-root)) nil nil nil)))
               (if (not (file-exists-p file-name))
                   (throw 'file-name file-name)
                 (when (y-or-n-p
                        (format "File `%s' exists; overwrite? " file-name))
                   (throw 'file-name file-name)))))))
        (output-buffer python-django-mgmt-output-buffer))
    (with-current-buffer (find-file-noselect file-name)
      (set (make-local-variable 'require-final-newline) t)
      (delete-region (point-min) (point-max))
      (insert output-buffer)
      (save-buffer)
      (kill-buffer))
    (kill-buffer)
    (python-django-mgmt-restore-window-configuration)
    (message "Fixture saved to file `%s'." file-name)))

(defalias 'python-django-qmgmt-dumpdata-app-callback
  'python-django-qmgmt-dumpdata-callback)
(defalias 'python-django-qmgmt-dumpdata-all-callback
  'python-django-qmgmt-dumpdata-callback)

(python-django-qmgmt-define flush
  "Execute 'sqlflush' on the given database."
  (:submenu "Database" :binding "df" :msg "Flushed database"
   (database (python-django-minibuffer-read-database "Database: " default)
             "default" "--database=")))

(defalias 'python-django-qmgmt-flush-callback
  'python-django-qmgmt-kill-and-msg-callback)

(python-django-qmgmt-define loaddata
  "Install the named fixture(s) in the database."
  (:submenu "Database" :binding "dl"
   (database (python-django-minibuffer-read-database "Database: " default)
             "default" "--database=")
   (fixtures (python-django-minibuffer-read-file-names "Fixtures: "))))

(defalias 'python-django-qmgmt-loaddata-callback
  'python-django-qmgmt-kill-and-msg-callback)

(python-django-qmgmt-define validate
  "Validate all installed models."
  (:submenu "Database" :binding "dv"))

(defalias 'python-django-qmgmt-validate-callback
  'python-django-qmgmt-kill-and-msg-callback)

(python-django-qmgmt-define graph_models-all
  "Creates a Graph of models for all project apps."
  (:submenu "Database" :switches "-ag"  :binding "dgg"
   (filename (read-file-name "Filename for generated Graph: "
                             default default)
             (expand-file-name
              "graph_all.png" python-django-project-root)
             "--output=" t)))

(python-django-qmgmt-define graph_models-apps
  "Creates a Graph of models for given apps."
  (:submenu "Database" :binding "dga"
   (apps (python-django-minibuffer-read-apps "Graph for App: "))
   (filename
    (expand-file-name
     (read-file-name "Filename for generated Graph: " default default))
    (expand-file-name
     (format "graph_%s.png" (replace-regexp-in-string " " "_" apps))
     python-django-project-root)
    "--output=" t)))

(defun python-django-qmgmt-graph_models-callback (args)
  "Callback for graph_model quick management command.
Optional argument ARGS args for it."
  (let ((open (y-or-n-p "Open generated graph? ")))
    (kill-buffer)
    (python-django-mgmt-restore-window-configuration)
    (and open
         (find-file (cdr (assoc 'filename args))))))

(defalias 'python-django-qmgmt-graph_models-all-callback
  'python-django-qmgmt-graph_models-callback)
(defalias 'python-django-qmgmt-graph_models-apps-callback
  'python-django-qmgmt-graph_models-callback)

;; i18n

(python-django-qmgmt-define makemessages-all
  "Create/Update translation string files."
  (:submenu "i18n" :switches "--all" :binding "im"))

(defalias 'python-django-qmgmt-makemessages-all-callback
  'python-django-qmgmt-kill-and-msg-callback)

(python-django-qmgmt-define compilemessages-all
  "Compile project .po files to .mo."
  (:submenu "i18n" :binding "ic"))

(defalias 'python-django-qmgmt-compilemessages-all-callback
  'python-django-qmgmt-kill-and-msg-callback)

;; Dev Server

(defcustom python-django-qmgmt-runserver-default-bindaddr "localhost:8000"
  "Default binding address for quick runserver."
  :group 'python-django
  :type 'string
  :safe 'stringp)

(defcustom python-django-qmgmt-testserver-default-bindaddr "localhost:8000"
  "Default binding address for quick testserver."
  :group 'python-django
  :type 'string
  :safe 'stringp)

(defcustom python-django-qmgmt-mail_debug-default-bindaddr "localhost:1025"
  "Default binding address for quick mail_debug."
  :group 'python-django
  :type 'string
  :safe 'stringp)

(python-django-qmgmt-define runserver
  "Start development Web server."
  (:submenu "Server" :binding "rr"
   (bindaddr "Serve on [ip]:[port]: "
             python-django-qmgmt-runserver-default-bindaddr)))

(python-django-qmgmt-define runserver_plus
  "Start extended development Web server."
  (:submenu "Server" :binding "rp"
   (bindaddr "Serve on [ip]:[port]: "
             python-django-qmgmt-runserver-default-bindaddr)))

(python-django-qmgmt-define testserver
  "Start development server with data from the given fixture(s)."
  (:submenu "Server" :binding "rt"
   (bindaddr "Serve on [ip]:[port]: "
             python-django-qmgmt-testserver-default-bindaddr)
   (fixtures (python-django-minibuffer-read-file-names "Fixtures: "))))

(python-django-qmgmt-define mail_debug
  "Start a test mail server for development."
  (:submenu "Server" :binding "rm"
   (bindaddr "Serve on [ip]:[port]: "
             python-django-qmgmt-mail_debug-default-bindaddr)))

;; Testing

(python-django-qmgmt-define test-all
  "Run the test suite for the entire project."
  (:submenu "Test" :binding "tp"))

(defalias 'python-django-qmgmt-test-all-callback
  'python-django-qmgmt-kill-and-msg-callback)

(python-django-qmgmt-define test-app
  "Run the test suite for the specified app."
  (:submenu "Test" :binding "ta"
   (app (python-django-minibuffer-read-app "Test App: "))))

(defalias 'python-django-qmgmt-test-app-callback
  'python-django-qmgmt-kill-and-msg-callback)

;; South integration

(python-django-qmgmt-define convert_to_south
  "Convert given app to South."
  (:submenu "South" :binding "soc"
   (app (python-django-minibuffer-read-app "Convert App: "))))

(defalias 'python-django-qmgmt-convert_to_south-callback
  'python-django-qmgmt-kill-and-msg-callback)

(python-django-qmgmt-define datamigration
  "Create a new datamigration for the given app."
  (:submenu "South" :binding "sod"
   (app (python-django-minibuffer-read-app "Datamigration for App: "))
   (name "Datamigration name: ")))

(defalias 'python-django-qmgmt-datamigration-callback
  'python-django-qmgmt-kill-and-msg-callback)

(python-django-qmgmt-define migrate-all
  "Run all migrations for all apps."
  (:submenu "South" :switches "--all" :binding "somp"
   (database (python-django-minibuffer-read-database "Database: " default)
             "default" "--database=")))

(defalias 'python-django-qmgmt-migrate-all-callback
  'python-django-qmgmt-kill-and-msg-callback)

(python-django-qmgmt-define migrate-app
  "Run all migrations for given app."
  (:submenu "South" :binding "soma"
   (database (python-django-minibuffer-read-database "Database: " default)
             "default" "--database=")
   (app (python-django-minibuffer-read-app "Migrate App: "))))

(defalias 'python-django-qmgmt-migrate-app-callback
  'python-django-qmgmt-kill-and-msg-callback)

(python-django-qmgmt-define migrate-app-to
  "Run migrations for given app [up|down]-to given number."
  (:submenu "South" :binding "somt"
   (database (python-django-minibuffer-read-database "Database: " default)
             "default" "--database=")
   (app (python-django-minibuffer-read-app "Migrate App: "))
   (migration (python-django-minibuffer-read-migration "To migration: " app))))

(defalias 'python-django-qmgmt-migrate-app-to-callback
  'python-django-qmgmt-kill-and-msg-callback)

(python-django-qmgmt-define schemamigration-initial
  "Create the initial schemamigration for the given app."
  (:submenu "South" :switches "--initial" :binding "sosi"
   (app (python-django-minibuffer-read-app
         "Initial schemamigration for App: "))))

(defalias 'python-django-qmgmt-schemamigration-initial-callback
  'python-django-qmgmt-kill-and-msg-callback)

(python-django-qmgmt-define schemamigration
  "Create new empty schemamigration for the given app."
  (:submenu "South" :switches "--empty" :binding "soss"
   (app (python-django-minibuffer-read-app
         "Initial schemamigration for App: "))))

(defalias 'python-django-qmgmt-schemamigration-callback
  'python-django-qmgmt-kill-and-msg-callback)

(python-django-qmgmt-define schemamigration-auto
  "Create an automatic schemamigration for the given app."
  (:submenu "South" :switches "--auto" :binding "sosa"
   (app (python-django-minibuffer-read-app
         "Auto schemamigration for App: "))))

(defalias 'python-django-qmgmt-schemamigration-auto-callback
  'python-django-qmgmt-kill-and-msg-callback)


;;; Fast commands

(defcustom python-django-cmd-etags-command
  "etags `find -name \"*.py\"`"
  "Command used to build tags tables."
  :group 'python-django
  :type 'string)

(defcustom python-django-cmd-grep-function nil
  "Function to grep on a directory.
The function receives no args, however `default-directory' will
default to a sane value."
  :group 'python-django
  :type 'function)

(defun python-django-cmd-build-etags ()
  "Build tags for current project."
  (interactive)
  (let ((current-dir default-directory))
    (cd
     (file-name-directory
      python-django-info-manage.py-path))
    (if (eq 0
            (shell-command
             python-django-cmd-etags-command))
        (message "Tags created sucessfully")
      (message "Tags creation failed"))
    (cd current-dir)))

(defun python-django-cmd-grep ()
  "Grep in project directories."
  (interactive)
  (let ((default-directory
          (or (python-django-ui-directory-at-point)
              (file-name-directory
               python-django-info-manage.py-path))))
    (if (not python-django-cmd-grep-function)
        (call-interactively #'rgrep)
      (funcall
       python-django-cmd-grep-function default-directory))))

(defun python-django-cmd-open-docs ()
  "Open Django documentation in a browser."
  (interactive)
  (browse-url
   (format
    "https://docs.djangoproject.com/en/%s/"
    (substring (python-django-info-get-version) 0 3))))

(defun python-django-cmd-visit-settings ()
  "Visit settings file."
  (interactive)
  (find-file (python-django-info-module-path
              python-django-settings-module)))

(defun python-django-cmd-visit-virtualenv ()
  "Visit virtualenv directory."
  (interactive)
  (and python-shell-virtualenv-path
       (dired python-shell-virtualenv-path)))

(defun python-django-cmd-visit-project-root ()
  "Visit project root directory."
  (interactive)
  (dired python-django-project-root))

(defun python-django-cmd-dired-at-point ()
  "Open dired at current tree node."
  (interactive)
  (let ((dir (python-django-ui-directory-at-point)))
    (and dir (dired dir))))

(defun python-django-cmd-directory-at-point ()
  "Message the current directory at point."
  (interactive)
  (message (or (python-django-ui-directory-at-point) "")))

(defun python-django-cmd-jump-to-app (app)
  "Jump to APP's directory."
  (interactive
   (list
    (python-django-minibuffer-read-app "Jump to app: " nil t)))
  (let ((app (assq (intern app)
                   (python-django-info-get-app-paths))))
    (when app
      (goto-char (point-min))
      (re-search-forward (format " %s" (car app)))
      (python-django-ui-move-to-closest-icon))))

(defun python-django-cmd-jump-to-media (which)
  "Jump to a WHICH media directory."
  (interactive
   (list
    (python-django-minibuffer-read-from-list
     "Jump to: " '("MEDIA_ROOT" "STATIC_ROOT"))))
  (goto-char (point-min))
  (re-search-forward (format " %s" which))
  (python-django-ui-move-to-closest-icon))

(defun python-django-cmd-jump-to-template-dir (which)
  "Jump to a WHICH template directory."
  (interactive
   (list
    (python-django-minibuffer-read-from-list
     "Jump to: "
     (mapcar 'identity (python-django-info-get-setting "TEMPLATE_DIRS")))))
  (goto-char (point-min))
  (re-search-forward (format " %s" which))
  (python-django-ui-move-to-closest-icon))



;;; UI stuff

(defvar python-django-ui-ignored-dirs
  '("." ".." ".bzr" ".cdv" "~.dep" "~.dot" "~.nib" "~.plst" ".git" ".hg" ".pc"
    ".svn" "_MTN" "blib" "CVS" "RCS" "SCCS" "_darcs" "_sgbak" "autom4te.cache"
    "cover_db" "_build" ".ropeproject")
  "Directories ignored when scanning project files.")

(defvar python-django-ui-allowed-extensions
  '("css" "gif" "htm" "html" "jpg" "js" "json" "mo" "png" "po" "py" "txt" "xml"
    "yaml" "scss" "less")
  "Allowed extensions when scanning project files.")

(defcustom python-django-ui-buffer-switch-function 'pop-to-buffer
  "Function for switching to the project buffer.
The function receives one argument, the status buffer."
  :group 'python-django
  :type '(radio (function-item switch-to-buffer)
                (function-item pop-to-buffer)
                (function-item display-buffer)
                (function :tag "Other")))

(defun python-django-ui-show-buffer (buffer)
  "Show the Project BUFFER."
  (funcall python-django-ui-buffer-switch-function buffer))

(defun python-django-ui-clean ()
  "Empty current UI buffer."
  (let ((inhibit-read-only t))
    (erase-buffer)))

(defun python-django-ui-insert-header ()
  "Draw header information."
  (insert
   (format "%s\t\t%s\n"
           (propertize
            "Django Version:"
            'face 'python-django-face-title)
           (propertize
            (python-django-info-get-version)
            'face 'python-django-face-django-version))
   (format "%s\t\t%s\n"
           (propertize
            "Project:"
            'face 'python-django-face-title)
           (propertize
            python-django-project-root
            'face 'python-django-face-project-root))
   (format "%s\t\t%s\n"
           (propertize
            "Settings:"
            'face 'python-django-face-title)
           (propertize
            python-django-settings-module
            'face 'python-django-face-settings-module))
   (format "%s\t\t%s"
           (propertize
            "Virtualenv:"
            'face 'python-django-face-title)
           (propertize
            (or python-shell-virtualenv-path "None")
            'face 'python-django-face-virtualenv-path))
   "\n\n\n"))

(defun python-django-ui-build-section-alist ()
  "Create section Alist for current project."
  (list
   (cons
    "Apps" (mapcar
            (lambda (app)
              (cons app (python-django-info-get-app-path app)))
            (python-django-info-get-setting "INSTALLED_APPS")))
   (cons
    "Media"
    (list
     (cons "MEDIA_ROOT" (python-django-info-get-setting "MEDIA_ROOT"))
     (cons "STATIC_ROOT" (python-django-info-get-setting "STATIC_ROOT"))))
   (cons
    "Templates" (mapcar
                 (lambda (dir)
                   (cons dir dir))
                 (python-django-info-get-setting "TEMPLATE_DIRS")))))

;; Many kudos to Ye Wenbin since dirtree.el was of great help when
;; looking for examples of `tree-widget':
;; https://github.com/zkim/emacs-dirtree/blob/master/
(define-widget 'python-django-ui-tree-section-widget 'tree-widget
  "Tree widget for sections of Django Project buffer."
  :expander 'python-django-ui-tree-section-widget-expand
  :help-echo 'ignore
  :has-children t)

(define-widget 'python-django-ui-tree-section-node-widget 'push-button
  "Widget for a nodes of `python-django-ui-tree-section-widget'."
  :format         "%[%t%]\n"
  :button-face    'default
  :notify         'python-django-ui-tree-section-widget-expand)

(define-widget 'python-django-ui-tree-dir-widget 'tree-widget
  "Tree widget for directories of Django Project."
  :expander 'python-django-ui-tree-dir-widget-expand
  :help-echo 'ignore
  :has-children t)

(define-widget 'python-django-ui-tree-file-widget 'push-button
  "Widget for a files inside the `python-django-ui-tree-dir-widget'."
  :format         "%[%t%]\n"
  :button-face    'default
  :notify         'python-django-ui-tree-file-widget-select)

(defun python-django-ui-tree-section-widget-expand (tree &rest ignore)
  "Expand directory for given section TREE widget.
Optional argument IGNORE is there for compatibility."
  (or (widget-get tree :args)
      (let ((section-alist (widget-get tree :section-alist)))
        (mapcar (lambda (section)
                  (let ((name (car section))
                        (dir (cdr section)))
                    `(python-django-ui-tree-dir-widget
                      :node (python-django-ui-tree-file-widget
                             :tag ,name
                             :file ,dir)
                      :file ,dir
                      :open nil
                      :indent 0)))
                section-alist))))

(defun python-django-ui-tree-dir-widget-expand (tree)
  "Expand directory for given TREE widget."
  (or (widget-get tree :args)
      (let* ((dir (widget-get tree :file))
             dir-list file-list)
        (when (and dir (file-exists-p dir))
          (dolist (file (directory-files dir t))
            (let ((basename (file-name-nondirectory file)))
              (if (file-directory-p file)
                  (when (not (member basename python-django-ui-ignored-dirs))
                    (setq dir-list (cons basename dir-list)))
                (when (member (file-name-extension file)
                              python-django-ui-allowed-extensions)
                  (setq file-list (cons basename file-list))))))
          (setq dir-list (sort dir-list 'string<))
          (setq file-list (sort file-list 'string<))
          (append
           (mapcar (lambda (file)
                     `(python-django-ui-tree-dir-widget
                       :file ,(expand-file-name file dir)
                       :node (python-django-ui-tree-file-widget
                              :tag ,file
                              :file ,file)))
                   dir-list)
           (mapcar (lambda (file)
                     `(python-django-ui-tree-file-widget
                       :file ,(expand-file-name file dir)
                       :tag ,file))
                   file-list))))))

(defun python-django-ui-tree-file-widget-select (node &rest ignore)
  "Open file in other window.
Argument NODE and IGNORE are just for compatibility."
  (let ((file (widget-get node :file)))
    (and file (find-file-other-window file))))

(defun python-django-ui-tree-section-insert (name section-alist)
  "Create tree widget for NAME and SECTION-ALIST."
  (apply 'widget-create
         `(python-django-ui-tree-section-widget
           :node (python-django-ui-tree-section-node-widget
                  :tag ,name)
           :section-alist ,section-alist
           :open t)))

(defun python-django-ui-widget-move (arg)
  "Widget movement.
With positive ARG move forward that many times, else backwards."
  (let* ((success-moves 0)
         (forward (> arg 0))
         (func (if forward
                   'widget-forward
                 'widget-backward))
         (abs-arg (abs arg)))
    (catch 'nowidget
      (while (> abs-arg success-moves)
        (ignore-errors (funcall func 1))
        (let ((widget (widget-at (point))))
          (when (not widget)
            (throw 'nowidget t))
          (when (eq (widget-get widget :help-echo) 'tree-widget-icon-help-echo)
            (setq success-moves (1+ success-moves))))))))

(defun python-django-ui-widget-forward (arg)
  "Move point to the next field or button.
With optional ARG, move across that many fields."
  (interactive "p")
  (python-django-ui-widget-move arg))

(defun python-django-ui-widget-backward (arg)
  "Move point to the previous field or button.
With optional ARG, move across that many fields."
  (interactive "p")
  (python-django-ui-widget-move (- arg)))

(defun python-django-ui-parent-widget-move (arg)
  "Widget movement.
With positive ARG move forward that many times, else backwards."
  (python-django-ui-widget-forward 1)
  (python-django-ui-widget-backward 1)
  (let ((start-depth (- (point) (line-beginning-position)))
        (func (if (>= 0 arg)
                  'python-django-ui-widget-backward
                'python-django-ui-widget-forward)))
    (when (not (= 0 start-depth))
      (while (<= start-depth (- (point) (line-beginning-position)))
        (funcall func 1)))))

(defun python-django-ui-parent-widget-forward (arg)
  "Move point to the next field or button.
With optional ARG, move across that many fields."
  (interactive "p")
  (python-django-ui-parent-widget-move arg))

(defun python-django-ui-parent-widget-backward (arg)
  "Move point to the previous field or button.
With optional ARG, move across that many fields."
  (interactive "p")
  (python-django-ui-parent-widget-move (- arg)))

(defun python-django-ui-beginning-of-widgets ()
  "Move point to the previous field or button.
With optional ARG, move across that many fields."
  (interactive)
  (goto-char (point-min))
  (python-django-ui-widget-forward 1))

(defun python-django-ui-end-of-widgets ()
  "Move point to the previous field or button.
With optional ARG, move across that many fields."
  (interactive)
  (goto-char (point-max))
  (python-django-ui-widget-backward 1))

(defun python-django-ui-move-to-closest-icon ()
  "Move to closest open/close icon from point."
  (interactive)
  (let ((widget (widget-at (point))))
    (when (not (member
                (car widget)
                '(tree-widget-close-icon
                  tree-widget-empty-icon
                  tree-widget-leaf-icon
                  tree-widget-open-icon)))
      (python-django-ui-widget-forward -1))))

(defun python-django-ui-safe-button-press ()
  "Move to closest open/close icon from point and press it."
  (interactive)
  (python-django-ui-move-to-closest-icon)
  (widget-button-press (point)))

(defvar python-django-ui-cycle-mgmt-opened-buffers-index 0)

(defun python-django-ui-cycle-mgmt-opened-buffers-forward ()
  "Cycle opened process buffers forward."
  (interactive)
  (let* ((buffers (python-django-mgmt-opened-buffers-for (current-buffer)))
         (newindex
          (if (= (length buffers)
                 (1+ python-django-ui-cycle-mgmt-opened-buffers-index))
              0
            (1+ python-django-ui-cycle-mgmt-opened-buffers-index))))
    (when buffers
      (set (make-local-variable
            'python-django-ui-cycle-mgmt-opened-buffers-index) newindex)
      (display-buffer (nth newindex buffers)))))

(defun python-django-ui-cycle-mgmt-opened-buffers-backward ()
  "Cycle opened process buffers backward."
  (interactive)
  (let* ((buffers (python-django-mgmt-opened-buffers-for (current-buffer)))
         (newindex
          (if (= python-django-ui-cycle-mgmt-opened-buffers-index 0)
              (1- (length buffers))
            (1- python-django-ui-cycle-mgmt-opened-buffers-index))))
    (when buffers
      (set (make-local-variable
            'python-django-ui-cycle-mgmt-opened-buffers-index) newindex)
      (display-buffer (nth newindex buffers)))))

(defun python-django-ui-widget-type-at-point ()
  "Return the node type for current position."
  (let* ((widget (widget-at (point)))
         (file-p (widget-get
                  (tree-widget-node widget)
                  :tree-widget--guide-flags)))
    (and widget (if file-p 'file 'dir))))

(defun python-django-ui-directory-at-point ()
  "Return the node type for current position."
  (widget-get
   (widget-get (tree-widget-node (widget-at (point))) :parent) :file))


;;;Main functions

(defcustom python-django-known-projects nil
  "Alist of known projects."
  :group 'python-django
  :type '(repeat (list string string string))
  :safe (lambda (val)
          (and
           (stringp (car val))
           (stringp (cadr val))
           (stringp (caddr val)))))

(defun python-django-mode-find-buffer (&optional project-name no-match)
  "Find Django project buffer.
Optional argument PROJECT-NAME is the project name to match
against.  Optional argument NO-MATCH causes the search to exclude
buffers that belong to PROJECT-NAME."
  (dolist (buf (buffer-list))
    (and (with-current-buffer buf
           (and (eq major-mode 'python-django-mode)
                (or (not project-name)
                    (if no-match
                        (not
                         (string= project-name
                                  python-django-info-project-name))
                      (string= project-name
                               python-django-info-project-name)))))
         (return buf))))

(defun python-django-mode-on-kill-buffer ()
  "Hook run on `buffer-kill-hook'."
  (and (python-django-mgmt-opened-buffers-for (current-buffer))
       (call-interactively 'python-django-mgmt-kill-all)))

(define-derived-mode python-django-mode special-mode "Django"
  "Major mode to manage Django projects.

\\{python-django-mode-map}")

;;;###autoload
(defun python-django-open-project (directory settings
                                             &optional existing-buffer)
  "Open a Django project at given DIRECTORY using SETTINGS.
Optional argument EXISTING-BUFFER is internal and should not be used.

The recommended way to chose your project root, is to use the
directory containing your settings module; for instance if your
settings module is in /path/django/settings.py, use /path/django/
as your project path and django.settings as your settings module.

When called with no `prefix-arg', this function will try to find
an opened project-buffer, if current buffer is already a project
buffer it will cycle to next opened project.  If no project
buffers are found, then the user prompted for the project path
and settings module unless `python-django-project-root' and
`python-django-settings-module' are somehow set, normally via
directory local variables.  If none of the above matched or the
function is called with one `prefix-arg' and there are projects
defined in the `python-django-known-projects' variable the user
is prompted for any of those known projects, if the variable
turns to be nil the user will be prompted for project-path and
settings module (the same happens when called with two or more
`prefix-arg')."
  (interactive
   (let ((buf
          ;; Get an existing project buffer that's not the current.
          (python-django-mode-find-buffer
           (and (eq major-mode 'python-django-mode)
                python-django-info-project-name) t)))
     (cond ((and (not current-prefix-arg) (not buf)
                 python-django-project-root
                 python-django-settings-module)
            ;; There's no existing buffer but project variables are
            ;; set, so use them to open the project.
            (list python-django-project-root
                  python-django-settings-module
                  (and (not buf)
                       (eq major-mode 'python-django-mode)
                       (current-buffer))))
           ((and (not current-prefix-arg) buf)
            ;; there's an existing buffer move/cycle to it.
            (with-current-buffer buf
              (list
               python-django-project-root
               python-django-settings-module
               buf)))
           ((or (and python-django-known-projects
                     (or (not current-prefix-arg)
                         (= (prefix-numeric-value current-prefix-arg) 4))))
            ;; When there are known projects and called with just one
            ;; prefix arg or none and other project input methods
            ;; failed.
            (cdr
             (assoc
              (python-django-minibuffer-read-from-list
               "Project: " python-django-known-projects)
              python-django-known-projects)))
           (t
            ;; When called with two or more prefix arguments or all
            ;; input methods failed.
            (list
             (read-directory-name
              "Project Root: " python-django-project-root nil t)
             (read-string
              (format
               "Settings module (default: %s): "
               (or python-django-settings-module "settings"))
              nil nil
              (or python-django-settings-module "settings")))))))
  (if (not existing-buffer)
      (let* ((project-name (python-django-info-directory-basename directory))
             (buffer-name (format "*Django: %s*" project-name))
             (success t))
        (with-current-buffer (get-buffer-create buffer-name)
          (let ((inhibit-read-only t))
            (python-django-mode)
            (python-django-ui-clean)
            (set (make-local-variable
                  'python-django-info--get-setting-cache) nil)
            (set (make-local-variable
                  'python-django-info--get-version-cache) nil)
            (set (make-local-variable
                  'python-django-info--get-app-paths-cache) nil)
            (set (make-local-variable
                  'python-django-project-root) directory)
            (set (make-local-variable
                  'python-django-settings-module) settings)
            (set (make-local-variable
                  'python-django-info-project-name) project-name)
            (set (make-local-variable
                  'python-django-info-manage.py-path)
                 (python-django-info-find-manage.py directory))
            (python-django-util-clone-local-variables)
            (python-django-ui-insert-header)
            (condition-case err
                (mapc (lambda (section)
                        (python-django-ui-tree-section-insert
                         (car section) (cdr section))
                        (insert "\n"))
                      (python-django-ui-build-section-alist))
              (error
               (setq success nil)
               (insert
                (format
                 (concat
                  "An error occurred retrieving project information.\n"
                  "Check your project settings and try again:\n\n"
                  "Current values:\n"
                  "  + python-django-project-root: %s\n"
                  "  + python-django-settings-module: %s\n"
                  "  + python-django-python-executable: %s\n"
                  "    - found in %s\n\n\n"
                  "Error: %s \n")
                 python-django-project-root
                 python-django-settings-module
                 python-django-python-executable
                 (let* ((process-environment
                         (python-django-info-calculate-process-environment))
                        (exec-path (python-shell-calculate-exec-path)))
                   (executable-find python-django-python-executable))
                 (error-message-string err))))))
          (when success
            (python-django-qmgmt-add-menu-items)
            (add-hook 'kill-buffer-hook
                      #'python-django-mode-on-kill-buffer nil t)
            (python-django-ui-beginning-of-widgets))
          (python-django-ui-show-buffer (current-buffer))))
    (python-django-ui-show-buffer existing-buffer)))

;; Stolen from magit.
(defun python-django-close-project (&optional kill-buffer)
  "Bury the buffer and delete its window.
With a prefix argument, KILL-BUFFER instead."
  (interactive "P")
  (quit-window kill-buffer (selected-window)))

(defun python-django-refresh-project ()
  "Refresh Django project."
  (interactive)
  (python-django-open-project
   python-django-project-root
   python-django-settings-module))

(provide 'python-django)

;; Local Variables:
;; coding: utf-8
;; indent-tabs-mode: nil
;; End:

;;; python-django.el ends here
