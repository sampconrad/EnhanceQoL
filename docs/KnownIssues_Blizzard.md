Known Issues – Blizzard

Issue: Secure Last Tell / Whisper Handling Taint and ChatFrame crashes

- Bug report: https://github.com/Stanzilla/WoWUIBugs/issues/780
- Affected: Chat whisper targets, ChatFrame temporary whisper windows, last‑tell taint.

Workaround implemented in this addon

- Feature name: EQOL Whisper Sink
- Summary: Route WHISPER and BN_WHISPER MessageGroups into a hidden chat frame so that Blizzard keeps managing last‑tell securely, while the standard chat stays free of whispers (rendered instead by our IM UI).

Implementation notes

- All changes are marked in code by comments starting with:
  --! EQOL Whisper Sink

- Files and key areas:
  - EnhanceQoL/Submodules/ChatIM/Core.lua
    - State: hidden sink + original groups
    - SetupWhisperSink / TrySetupWhisperSink / RestoreWhisperGroups
    - Event registration changes (PLAYER_LOGIN, UPDATE_CHAT_WINDOWS, PLAYER_LOGOUT)
    - Reply helper /eimr using securecall(ChatFrame_OpenChat, SLASH_REPLY1.." ")
  - EnhanceQoL/Submodules/ChatIM/UI.lua
    - Removed ChatEdit_SetLastToldTarget/ChatEdit_SetLastTellTarget (outbound), marked with the same tag

How to revert when Blizzard fixes the bug

1) In Core.lua:
   - Remove the entire block between:
     --! EQOL Whisper Sink BEGIN
     ...
     --! EQOL Whisper Sink END
   - In updateRegistration(): remove the two tagged register lines and any tagged comments.
   - In SetEnabled(): remove the tagged TrySetupWhisperSink call and disable‑restore tag.
   - Remove the optional /eimr reply helper block (tagged).

2) In UI.lua:
   - In ChatIM:AddMessage(), restore (or reintroduce) ChatEdit_SetLastToldTarget / ChatEdit_SetLastTellTarget if desired.

3) Validate:
   - Whispers show again in default chat
   - Reply key /r behaves as expected

Rationale

- Opening temporary whisper windows without a valid target may crash internal ChatFrame code (nil target, math.max on nil), and manual ChatEdit_* calls can cause taint in edge cases. MessageGroup routing avoids both issues while preserving Blizzard’s secure last‑tell.

