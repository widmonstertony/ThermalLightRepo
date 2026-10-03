# Third-party notice

NewT66y/小草, its IPA, executable code, application bundle, icon, resources,
name, and service content are not part of this repository and are not licensed
under the MIT License in this directory.

The historical upstream repository identified the iOS project as a binary-only
download page rather than an open-source project. This builder therefore does
not fetch or contain that application. A user must independently obtain and be
authorized to use the input IPA.

The reference SHA-256 in `build.sh` identifies only the input copy used for
local compatibility testing. It is not a grant of rights, an endorsement, or a
statement of ownership.

`patch-source/`, `payload/NewTWebFixV8-ios.dylib`, and
`tools/inject_macho.py` are original NewTWebFix compatibility components by
tony. They are distributed under GNU Affero General Public License v3; see
`PATCH-LICENSE-AGPL-3.0.txt`. The local packaging scripts and documentation in
this directory remain under the MIT License in `LICENSE`.

The download bridge interoperates with VidCatch v0.3.0. On iPad it uses Apple
URLSession and AVFoundation directly; on Mac it connects only to the user's
local VidCatch companion at `127.0.0.1:17368`. No hosted download service is
bundled or contacted by this builder.
