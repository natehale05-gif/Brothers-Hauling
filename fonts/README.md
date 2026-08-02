# Bundled fonts

Archivo, Archivo Black and DM Mono, all under the SIL Open Font License 1.1
(see the `OFL-*.txt` files here).

They are committed rather than fetched at runtime on purpose. The original web
prototype pulled them from Google Fonts on every load, which means a driver in a
dead spot — or anyone on a network that can't reach `fonts.googleapis.com` —
gets a different-looking app. Bundling them makes every platform render
identically, offline included.

To refresh a weight, download the static TTF from Google Fonts and keep the file
name; `pubspec.yaml` maps each file to its weight.
