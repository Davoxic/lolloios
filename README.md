# Lollo iOS (lolloios) 🎵

Porting nativo per **iOS** dell'applicazione musicale **Lollo** (precedentemente disponibile come APK Android).

L'app mantiene la stessa architettura, logica e librerie dell'APK originale, con tutte le ottimizzazioni necessarie per funzionare al meglio su iPhone:
- **Streaming audio YouTube nativo**: estrazione flussi AAC / MP4 ottimizzati per Apple AVPlayer (nessun errore 403 o blocco formati).
- **Riproduzione in background**: supporto nativo per lock screen e Centro di Controllo (titolo, artista, cover, controlli play/pausa/seek/avanti/indietro).
- **Gestione Playlist**: creazione, eliminazione, aggiunta brani e rimozione persistite su storage locale (`music_library_playlists_v1`).
- **Ricerca YouTube**: ricerca istantanea dei brani con durata, artista e miniature.
- **Interfaccia Dark Theme**: design pulito e reattivo in stile Material 3 / Cupertino.

---

## 🚀 Come scaricare e installare l'app su iPhone

1. Vai nella scheda [**Actions**](https://github.com/Davoxic/lolloios/actions) del repository.
2. Clicca sull'ultima esecuzione del workflow **Build IPA (unsigned)**.
3. In fondo alla pagina, nella sezione **Artifacts**, scarica il file **`lolloios-unsigned-ipa`**.
4. Estrai lo zip per ottenere `lolloios-unsigned.ipa`.
5. Installa e firma il file `.ipa` sul tuo iPhone utilizzando uno dei seguenti metodi gratuiti:
   - **[Sideloadly](https://sideloadly.io/)** (Windows / macOS)
   - **[AltStore](https://altstore.io/)**
   - **[TrollStore](https://github.com/opa334/TrollStore)** (se su versioni iOS compatibili)
   - **[Scarlet](https://usescarlet.com/)** o **LiveContainer**

---

## 🛠 Stack Tecnologico
- **Framework**: Flutter (Dart)
- **Audio Engine**: `just_audio` + `audio_session`
- **Background Playback**: `just_audio_background` (integrazione nativa con `MPNowPlayingInfoCenter` e `MPRemoteCommandCenter`)
- **YouTube Engine**: `youtube_explode_dart` con client iOS/AndroidVR
- **Storage**: `shared_preferences`
- **CI/CD**: GitHub Actions su runner `macos-latest` con Xcode
