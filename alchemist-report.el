;;; alchemist-report.el --- Run command in a process and handles buffer of it

;; Copyright © 2015 Samuel Tonini

;; Author: Samuel Tonini <tonini.samuel@gmail.com

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program. If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Run command in a process and handles buffer output and display

;;; Code:

(require 'ansi-color)
(require 'alchemist-project)

(defgroup alchemist-report nil
  "Run command in a process and handles buffer output and display"
  :prefix "alchemist-report-"
  :group 'alchemist)

(defvar alchemist-report-on-exit nil)
(defvar alchemist-report-on-exit-function nil)
(defvar alchemist-report-on-render nil)
(defvar alchemist-report-on-render-function nil)
(defvar alchemist-report--last-run-status nil)
(defvar alchemist-report-mode-name nil)

(defun alchemist-report--kill-process (process)
  "Interrupt and kill the running report PROCESS."
  (when process
    (let ((mode-name (replace-regexp-in-string ":.+$" "" mode-name)))
      (if (or (not (eq (process-status process) 'run))
              (eq (process-query-on-exit-flag process) nil)
              (yes-or-no-p
               (format "A %s process already running; kill it? "
                       mode-name)))
          (condition-case ()
              (progn
                (interrupt-process process)
                (sit-for 1)
                (delete-process process))
            (error nil))
        (error "Cannot have two processes in `%s' at once"
               (buffer-name))))))

(defun alchemist-report--sentinel (process status)
  "Sentinel for test report buffer."
  (if (memq (process-status process) '(exit signal))
      (let ((buffer (process-buffer process)))
        (if (null (buffer-name buffer))
            (set-process-buffer process nil)
          (progn
            (alchemist-report--render-report buffer)
            (alchemist-report--handle-exit status)
            (alchemist-report-update-mode-name process)
            (delete-process process))))))

(defun alchemist-report--render-report (buffer)
  "Call the defined render functions for the BUFFER."
  (when alchemist-report-on-render-function
    (funcall alchemist-report-on-render-function buffer)))

(defun alchemist-report--handle-exit (status)
  "Call the defined exit function specified in `alchemist-report-on-exit-function'.
Argument for the exit function is the STATUS of the finished process."
  (alchemist-report--store-process-status status)
  (when alchemist-report-on-exit-function
    (funcall alchemist-report-on-exit-function status)))

(defun alchemist-report--store-process-status (status)
  "Store STATUS of the last finished process."
  (setq alchemist-report--last-run-status status))

(defun alchemist-report--last-run-successful-p ()
  "Return non-nil if the last process successfully finished."
  (when (string-prefix-p "finished" alchemist-report--last-run-status) t))

(defun alchemist-report--ansi-color-insertion-filter (process output)
  "Process filter for report buffers.
Just apply ansi escape sequences to OUTPUT of PROCESS."
  (with-current-buffer (process-buffer process)
    (let* ((buffer-read-only nil)
           (moving (= (point) (process-mark process))))
      (save-excursion
        (goto-char (process-mark process))
        (insert output)
        (set-marker (process-mark process) (point))
        (ansi-color-apply-on-region (point-min) (point-max)))
      (if moving (goto-char (process-mark process))))))

(defun alchemist-report-update-mode-name (process)
  "Update the `mode-name' with the status of PROCESS."
  (with-current-buffer (process-buffer process)
    (setq mode-name (format "%s:%s"
                            (replace-regexp-in-string ":.+$" "" mode-name)
                            (process-status process)))))

(defun alchemist-report-interrupt-current-process ()
  "Interrupt the current running report process."
  (interactive)
  (let ((buffer (current-buffer))
        (name (replace-regexp-in-string ":.+" "" mode-name)))
    (if (get-buffer-process buffer)
        (interrupt-process (get-buffer-process buffer))
      (error "The [%s] process is not running" (downcase name)))))

(defun alchemist-report-cleanup-process-buffer (buffer)
  "Clean the content BUFFER of process.
If there is already a running process, ask for interrupting it."
  (with-current-buffer buffer
    (let ((inhibit-read-only t)
          (process (get-buffer-process buffer)))
      (alchemist-report--kill-process process)
      (erase-buffer)
      )))

(defun alchemist-report-display-buffer (buffer)
  "Display the BUFFER."
  (display-buffer buffer))

(defun alchemist-report-activate-mode (mode buffer)
  "Enable MODE inside BUFFER."
  (with-current-buffer buffer
    (funcall mode)
    (setq-local window-point-insertion-type t)))

(defun alchemist-report-run (command process-name buffer-name mode &optional on-exit on-render)
  "Run COMMAND in a new process called PROCESS-NAME.
The output of PROCESS-NAME will be displayed in BUFFER-NAME.
After displaying BUFFER-NAME, the MODE function will be called within.

Optional ON-EXIT and ON-RENDER functions could be defined.
These functions will be called when PROCESS-NAME is finished."
  (let* ((buffer (get-buffer-create buffer-name))
         (project-root (alchemist-project-root))
         (default-directory (if project-root
                                project-root
                              default-directory))
         (process (progn
                    (alchemist-report-cleanup-process-buffer buffer-name)
                    (start-process-shell-command process-name buffer command))))
    (when on-exit
      (setq alchemist-report-on-exit-function on-exit))
    (when on-render
      (setq alchemist-report-on-render-function on-render))
    (set-process-sentinel process 'alchemist-report--sentinel)
    (set-process-filter process 'alchemist-report--ansi-color-insertion-filter)
    (alchemist-report-activate-mode mode buffer)
    (alchemist-report-display-buffer buffer)
    (alchemist-report-update-mode-name process)))

(provide 'alchemist-report)

;;; alchemist-report.el ends here
