# Goul personal MVP adaptation

User-authorized scope: separate folder, rename and personalize Murmur as Goul, One Piece / Straw Hat design, install and launch on this Mac, English first.

1. Give the app an independent bundle identity and resources.
2. Remove Wispr cloud-comparison integration. Keep Apple speech default and optional local Parakeet. Force Apple locale to en-US.
3. Add cancellation/session isolation, target validation and clipboard ownership protection. Test these decisions and the existing dictionary.
4. Build a nautical logbook interface, generated Straw Hat icon, visible setup/permission controls, and a test recording mode that only displays text.
5. Build, sign, install Goul.app and launch. Verify UI and settings; user grants macOS permissions and speaks for the real microphone trial.

French: done as automatic English/French detection (2026-09-30). Parakeet v3 is the
default engine; Apple Speech arbitrates between two locked transcribers. Details, measurements
and limits in `docs/LANGUAGE-DETECTION.md`. Original upstream remains untouched in ../murmur-youtube.
