// Custom Flutter web bootstrap.
//
// The default loader fetches the CanvasKit renderer from
// https://www.gstatic.com/flutter-canvaskit/<hash>/, but `flutter build web`
// already emits a copy into build/web/canvaskit/. Pointing at the local copy
// means the app has no third-party CDN dependency at runtime: it renders on an
// air-gapped network, in a locked-down corporate environment, and in CI — and it
// cannot break because a CDN is unreachable.
{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: {
    canvasKitBaseUrl: 'canvaskit/',
  },
});
