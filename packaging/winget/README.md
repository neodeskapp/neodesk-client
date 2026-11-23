# winget manifests

`make_manifests.py` writes the winget manifests of a stable client release
(package identifier NeoDesk.NeoDesk, the x64 and arm64 MSI packages). The
workflow `.github/workflows/neodesk-packages.yml` runs it for every stable
desktop-v* release and keeps the result as the artifact
`winget-manifests-<tag>`.

Submitting is done by hand, because it is a pull request to
microsoft/winget-pkgs:

    winget validate --manifest manifests/n/NeoDesk/NeoDesk/<version>
    wingetcreate submit manifests/n/NeoDesk/NeoDesk/<version>

or a fork of microsoft/winget-pkgs with the folder copied to the same path.
The MSI installs per machine; winget passes the usual msiexec switches
(/quiet, /passive). The portable exe installs silently with
`--silent-install`, but the manifests only list the MSI.
