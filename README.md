GDrive-Sync
===========

gdrive-sync is a [Ruby][ruby-lang] program watching a given list of files and
upon change pushing it up to [Google Drive][google-drive] with the help of
[drive][drive-prg].


License
-------

Copyright Márk Szabadkai.

Under the [GNU General Public License v3][gpl-v3] (or see the `LICENSE.txt` file).


ToDo
----

- [ ] Use Rake to setup/tear down a user session bound System-D service
- [ ] Sync whole directories
- [ ] Handle globs or regexps in pathes


[ruby-lang]: https://www.ruby-lang.org/en/
[google-drive]: https://www.google.com/drive/
[drive-prg]: https://github.com/odeke-em/drive
[gpl-v3]: https://www.gnu.org/licenses/gpl-3.0.en.html
