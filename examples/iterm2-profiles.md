# iTerm2 Profile Integration

iTerm2 Profiles can launch a terminal tab pre-configured for a specific `gcenv` environment. This means one click (or one keyboard shortcut) opens a GCP-isolated terminal with the correct project, credentials, and a color-coded background — no manual `gcenv use` required.

---

## Creating a Profile

Follow these steps for each environment you want a dedicated profile for:

1. Open **iTerm2** and go to **Preferences** → **Profiles** → click **`+`** to create a new profile.

2. **Name**: Give the profile a descriptive name, e.g., `GCP: dev` or `GCP: prod`.

3. **General tab** → **Command**: Set to **Login shell** (the default). Do not use a custom shell command here.

4. **General tab** → **Send text at start**: Type the following (press **Enter** inside the text box to insert a literal newline after the command):

   ```
   gcenv use dev
   ```

   The literal newline causes iTerm2 to execute the command automatically when the tab opens, as if you typed it and pressed Return.

5. **Colors tab**: Optionally set a **Background Color** tint to visually distinguish environments at a glance. A subtle tint is more readable than a fully saturated color:
   - **dev** → light blue tint
   - **prod** → light red/orange tint (as a visual warning)
   - **staging** → light green tint

---

## Launching a Profile

- Press **`Cmd+O`** to open the Profile picker, then select your profile.
- Or use **Shell** → **New Window** / **New Tab** with a specific profile.
- Profiles can also be assigned keyboard shortcuts in **Preferences** → **Keys**.

---

## Tab Badge

`gcenv` automatically sets the iTerm2 tab badge to the active environment name using the iTerm2 proprietary escape sequence `ESC]1337;SetBadgeFormat`. This is sent by `_gcenv_set_terminal_title` whenever an environment is activated (`gcenv use`, `gcenv init`, `gcenv import`) and cleared on `gcenv deactivate` or `gcenv delete`.

The badge displays in the upper-right corner of each tab, providing a persistent at-a-glance indicator of which GCP environment is active — even when the prompt is scrolled off screen.

To enable tab badges in iTerm2: **Preferences** → **Profiles** → **General** → **Badge** — ensure it is set to show (the default).

---

## Example Profiles

| Profile Name | Send text at start | Background tint | Use case |
|---|---|---|---|
| `GCP: dev` | `gcenv use dev` + Enter | Blue (`#e8f4fd`) | Day-to-day development |
| `GCP: prod` | `gcenv use prod` + Enter | Red/orange (`#fff0e8`) | Production access (visually alarming by design) |
| `GCP: staging` | `gcenv use staging` + Enter | Green (`#edfde8`) | Staging validation |
| `GCP: ci` | `gcenv use ci` + Enter | Grey (`#f5f5f5`) | Service account / CI credential testing |

---

## Tips

- **Confirm before acting in prod**: Consider adding a second line to the prod profile's "Send text at start" field, such as `echo "⚠️  PRODUCTION environment active"`, to produce a visible warning each time the tab opens.
- **Profile hotkeys**: Assign `Cmd+Shift+1`, `Cmd+Shift+2`, etc. to your most-used profiles under **Preferences** → **Keys** → **Key Bindings**.
- **Window arrangements**: Use **Window** → **Save Window Arrangement** to save a layout with multiple pre-configured GCP tabs open simultaneously.
