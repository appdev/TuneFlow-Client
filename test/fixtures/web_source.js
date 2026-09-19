/*
 * @name Web browser integration fixture
 * @description Local-only import, export, playback and download verification
 * @version 1.0.0
 */
window.tuneflow.on(window.tuneflow.EVENT_NAMES.request, async ({ source, action }) => {
  if (source !== 'kw') throw new Error('Unexpected source')
  if (action === 'musicUrl') return 'http://127.0.0.1:8790/test-audio.mp3'
  throw new Error('Unsupported fixture action')
})
window.tuneflow.send(window.tuneflow.EVENT_NAMES.inited, {
  sources: { kw: { type: 'music', actions: ['musicUrl'], qualitys: ['128k'] } },
})
