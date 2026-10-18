# claude-cli-context

A status line and chat themes for [Claude Code](https://claude.com/claude-code) in the terminal.

The status line keeps context use, the 5-hour and weekly usage limits, and where your current pace takes them in view at all times. The session name goes on its own bold row:

```
ctx █░░░░░░░ 14% 141k/1M │ 5h 39% reset 40m, ends 51% (16%/h) │ wk 9% reset 6d 21h, out 1d 3h (3.3%/h) │ Opus 5.5 xhigh │ ~
my session name
```

The Chat themes put your own messages on a tinted block, so a long chat is easier to scan.

## Reading the status line

| Part | Meaning |
| --- | --- |
| `ctx █░░░░░░░ 14% 141k/1M` | Context window used: bar, percent, tokens used of the window size. |
| `5h 39%`, `wk 9%` | How much of the 5-hour and weekly limits is used. |
| `reset 40m` | Time until that limit resets. |
| `ends 51%` | Where usage will be when it resets, if the current pace holds. |
| `out 1d 3h` | Projected to reach 100% before it resets: time until it does. |
| `full` | Limit reached. |
| `(16%/h)` | The pace now. |
| `Opus 5.5 xhigh` | Model and effort level. |
| `~` | Current folder. |

Values are bold white while fine, amber from 50% and red from 80%. `out` and `full` are always red.

### How the projection works

Every refresh records each limit's value in `~/.cache/claude-statusline/` (shared by all sessions on the machine). The projection fits a curve to the current window's history by weighted least squares:

- Recent samples count most, with a half-life of 1 hour for the 5-hour limit and 1 day for the weekly one, so nights average out.
- The curve is anchored at 0% when the window opened.
- It is a straight line until the history covers at least the time left before reset; then it is a quadratic, so speeding up or slowing down shows. A curve is never extrapolated further than it was observed.
- If the fitted curve is falling now, usage has levelled off and the pace is taken as flat.
- Nothing is projected in a window's first 10 minutes.

Early in a weekly window a few busy hours get extrapolated over the whole week, so `out` can show too early until there is about a day of history.

## Requirements

- Claude Code. The limits appear when it includes `rate_limits` in the status line input; otherwise they are left out.
- `bash`, `jq`, `awk`.
- macOS for the light and dark palettes (it reads `defaults read -g AppleInterfaceStyle`). Elsewhere the dark palette is used.

Tested with Claude Code 2.1.302 in macOS Terminal.app.

## Install

```sh
git clone https://github.com/tushar9989/claude-cli-context.git
cd claude-cli-context
make install
```

`make install`:

- copies `statusline.sh` to `~/.claude/`, and the Chat themes to `~/.claude/themes/` (creating `chat-auto.json` if you don't have one);
- sets `statusLine` in `~/.claude/settings.json` and keeps your other settings;
- backs up any file it replaces with something different as `<file>.bak-<date>-<time>`, so running it again changes nothing.

`make install CLAUDE_DIR=<folder>` installs somewhere else, for example to try it out first. Then pick a Chat theme with `/theme` (see below).

To install by hand instead, copy `statusline.sh` to `~/.claude/`, make it executable, and add this to `~/.claude/settings.json`:

```json
"statusLine": {
  "type": "command",
  "command": "~/.claude/statusline.sh",
  "padding": 0,
  "refreshInterval": 60
}
```

`refreshInterval` redraws it every 60 seconds, so the countdowns move while Claude Code is idle.

### Chat themes

Pick **Chat (dark)**, **Chat (light)** or **Chat (auto)** with `/theme`. Claude Code watches `~/.claude/themes/` for changes, but only if the folder existed when it started, so restart it once if the install just created the folder.

**Chat (auto)** follows the macOS appearance. Custom themes can't have an automatic base, so the status line keeps `chat-auto.json` a copy of the dark or light theme, whichever matches the appearance, and Claude Code reloads it live. Delete the file to stop.

By hand: copy `themes/chat-dark.json` and `themes/chat-light.json` into `~/.claude/themes/`, and for Chat (auto) also a copy of either one named `chat-auto.json`.

To change the colours, edit `userMessageBackground` in the dark and light files. Colours can be `ansi256(n)`, `rgb(r,g,b)` or `#rrggbb`.

## Notes on Terminal.app

- Claude Code draws only 256 colours in Terminal.app, even though the terminal reports true colour. The script uses explicit 256-colour codes and matches Claude Code's own rgb-to-256 mapping, so the reset times show in the same colour as inline code in the chat.
- Faint text fades into the background in Terminal.app, so the script never uses it.

## License

[MIT](LICENSE)
