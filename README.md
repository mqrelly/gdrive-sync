GDrive-Sync
===========

gdrive-sync is a [Ruby][ruby-lang] program watching a given list of files and
upon change pushing it up to [Google Drive][google-drive] with the help of
[drive][drive-prg].


How does it work?
-----------------

The program watches local file changes. Upon a change the hash of the local and
cloud versions are checked. When only the local file changed since the last check,
it gets uploaded. If the cloud version is changed however, the program notifies
the user (via `notify-send`) and waits for the user to resolve the conflict.
Once the conflict is resolved, it resumes syncing automatically.

This is basically a one-way sync service.


How to use it?
--------------

The program assumes you already set up [drive][drive-prg] for the files you want
to keep in sync.

After that you only need a configuration file (named `gdrive-sync.config.yaml`)
in [YAML][yaml] format. The config should contain one list, named
`watch_files`. The list should contain file paths.

You should put the config file next to program, or pass its path as an argument
to the program.


License
-------

Copyright Márk Szabadkai.

Under the [GNU General Public License v3][gpl-v3] (or see the `LICENSE.txt` file).


ToDo
----

- [ ] Use Rake to setup/tear down a user session bound System-D service
- [ ] Sync whole directories
- [ ] Handle globs or regexps in a watch path


[ruby-lang]: https://www.ruby-lang.org/en/
[google-drive]: https://www.google.com/drive/
[drive-prg]: https://github.com/odeke-em/drive
[gpl-v3]: https://www.gnu.org/licenses/gpl-3.0.en.html
[yaml]: http://yaml.org/
