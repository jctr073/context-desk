## Slack Formatting Guide

Slack uses a lightweight markup syntax (similar to Markdown) for styling messages. You can either type the syntax directly or use the formatting toolbar in the message box.

## Text Styling

| Format           | Syntax         | Example Input         | Result                     |
| ---------------- | -------------- | --------------------- | -------------------------- |
| Bold             | `*text*`       | `*hello*`             | **hello**                  |
| Italic           | `_text_`       | `_hello_`             | *hello*                    |
| Strikethrough    | `~text~`       | `~hello~`             | ~~hello~~                  |
| Inline code      | `` `text` ``   | `` `hello` ``         | `hello`                    |
| Code block       | ` ```text``` ` | ` ```print("hi")``` ` | Multi-line monospace block |
| Blockquote       | `> text`       | `> quoted line`       | Indented quote             |
| Multi-line quote | `>>> text`     | `>>> long text`       | Quotes everything after    |

Note: Slack uses single asterisks for bold (not double) and underscores for italics (not single asterisks). This differs from standard Markdown.

## Lists

- Bulleted list: start a line with `- ` or `* `
- Numbered list: start a line with `1. `, `2. `, etc.
- Nested lists: indent with the Tab key

Example:

```
1. First item
2. Second item
   - Sub bullet
   - Another sub bullet
```

## Links

- Auto-linked URL: paste `https://slack.com`
- Named link: `<https://slack.com|Visit Slack>` renders as a clickable "Visit Slack"
- Email: `<mailto:team@example.com|Email the team>`

## Mentions and Channels

| Purpose                    | Syntax          | Example                          |
| -------------------------- | --------------- | -------------------------------- |
| Mention a user             | `@username`     | `@alice`                         |
| Mention a user group       | `@groupname`    | `@designers`                     |
| Link to a channel          | `#channel-name` | `#general`                       |
| Notify everyone in channel | `@channel`      | Notifies active and away members |
| Notify only active members | `@here`         | Less disruptive ping             |
| Notify entire workspace    | `@everyone`     | Use only in #general             |

## Emoji

- Use the colon syntax: `:smile:`, `:tada:`, `:rocket:`
- Custom workspace emoji follow the same pattern: `:partyparrot:`
- Skin tone modifiers: `:wave::skin-tone-3:`

## Date and Time Formatting

Slack can render localized timestamps for each viewer:

```
<!date^1717689600^{date_short_pretty} at {time}|Jun 6, 2024 at 12:00 PM>
```

Tokens you can use inside the curly braces:

- `{date_num}` -> 2024-06-06
- `{date}` -> June 6th, 2024
- `{date_short}` -> Jun 6, 2024
- `{date_long}` -> Thursday, June 6th, 2024
- `{date_pretty}` -> yesterday / today / tomorrow when applicable
- `{time}` -> 12:00 PM
- `{time_secs}` -> 12:00:00 PM

## Special Mentions in mrkdwn (Bots and API)

When sending messages via the Slack API using `mrkdwn`, use these tokens:

- `<@U12345678>` mentions a user by ID
- `<#C12345678|channel-name>` links a channel
- `<!subteam^S12345678|@designers>` mentions a user group
- `<!here>`, `<!channel>`, `<!everyone>` for broadcast pings
- `<!date^...>` for dynamic timestamps

## Code Examples with Syntax Highlighting

Slack does not currently support language hints inside triple backticks, but the code block still renders cleanly:

```

```

def greet(name): return f"Hello, {name}!"

```

```

## Dividers and Structure (Block Kit)

For richer messages sent via apps or workflows, Block Kit JSON supports:

- `section` blocks with `mrkdwn` text
- `divider` blocks for horizontal rules
- `header` blocks for large titles
- `context` blocks for small footnotes
- `actions` blocks for buttons

Example block:

```json
{
  "type": "section",
  "text": { "type": "mrkdwn", "text": "*Deploy complete* :rocket:" }
}
```

## Tips and Gotchas

- Asterisks and underscores must touch the text with no inner spaces (`*bold*` works, `* bold *` does not).
- To show a literal character, wrap it in inline code: `` `*not bold*` ``.
- Pressing Shift+Enter creates a new line without sending.
- Pressing Ctrl+Z (Cmd+Z on Mac) right after sending undoes formatting if you used the toolbar.
- You can disable Markdown-style input under Preferences > Advanced > "Format messages with markup" if you prefer the toolbar only.

## Quick Cheat Sheet

```
*bold*               _italic_              ~strike~
`inline code`        ```code block```      > quote
- bullet             1. numbered           >>> long quote
<url|label>          :emoji:               @user  #channel
```