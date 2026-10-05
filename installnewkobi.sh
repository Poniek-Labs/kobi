#!/usr/bin/env bash
set -e

INSTALL_PATH="/usr/local/bin/kobi"

echo "Installing Kobi Editor to ${INSTALL_PATH}..."

cat << 'EOF' > "${INSTALL_PATH}"
#!/usr/bin/env python3
import curses
import os
import sys
import termios
import tty


class KobiEditor:

  def __init__(self, stdscr, filename="untitled.txt"):
    self.stdscr = stdscr
    self.filename = filename
    self.lines = [""]
    self.cy = 0
    self.cx = 0
    self.row_offset = 0
    self.col_offset = 0
    self.status = "READY"

    self.load_file()
    self.init_curses()

  def init_curses(self):
    curses.curs_set(1)
    self.stdscr.keypad(True)
    curses.use_default_colors()

    # Themes
    curses.init_pair(1, curses.COLOR_BLACK, curses.COLOR_CYAN)  # Header
    curses.init_pair(2, curses.COLOR_WHITE, curses.COLOR_BLUE)  # Status footer
    curses.init_pair(3, curses.COLOR_CYAN, -1)  # Line numbers & Borders

  def load_file(self):
    if os.path.exists(self.filename):
      try:
        with open(self.filename, "r", encoding="utf-8") as f:
          content = f.read().splitlines()
          self.lines = content if content else [""]
      except Exception as e:
        self.status = f"Error loading file: {e}"

  def save_file(self):
    try:
      with open(self.filename, "w", encoding="utf-8") as f:
        for line in self.lines:
          f.write(line + "\n")
      self.status = f"Saved: {self.filename}"
    except Exception as e:
      self.status = f"Save error: {e}"

  def prompt(self, message):
    h, w = self.stdscr.getmaxyx()
    if h < 4 or w < 10:
      return ""

    self.stdscr.attron(curses.color_pair(2))
    self.stdscr.addstr(h - 1, 0, " " * (w - 1))
    self.stdscr.addstr(h - 1, 1, message[: max(1, w - 2)])
    self.stdscr.attroff(curses.color_pair(2))

    curses.echo()
    curses.curs_set(1)
    input_start = len(message) + 1
    max_len = max(1, w - input_start - 1)

    query = ""
    if input_start < w - 1:
      query = (
          self.stdscr.getstr(h - 1, input_start, max_len)
          .decode("utf-8", errors="ignore")
          .strip()
      )

    curses.noecho()
    return query

  def search(self):
    query = self.prompt("Search: ")
    if not query:
      self.status = "Search canceled"
      return

    # Forward search
    for idx in range(self.cy, len(self.lines)):
      line = self.lines[idx]
      start_col = (self.cx + 1) if idx == self.cy else 0
      pos = line.find(query, start_col)
      if pos != -1:
        self.cy = idx
        self.cx = pos
        self.status = f"Found '{query}' at line {idx + 1}"
        return

    # Wrap around search
    for idx in range(0, self.cy + 1):
      line = self.lines[idx]
      pos = line.find(query)
      if pos != -1:
        self.cy = idx
        self.cx = pos
        self.status = f"Found '{query}' at line {idx + 1}"
        return

    self.status = f"Not found: '{query}'"

  def scroll_viewport(self, text_height, text_width):
    # Keep row/col view offsets strictly constrained to printable viewport
    if self.cy < self.row_offset:
      self.row_offset = self.cy
    if self.cy >= self.row_offset + text_height:
      self.row_offset = self.cy - text_height + 1

    if self.cx < self.col_offset:
      self.col_offset = self.cx
    if self.cx >= self.col_offset + text_width:
      self.col_offset = self.cx - text_width + 1

  def render(self):
    self.stdscr.erase()
    h, w = self.stdscr.getmaxyx()

    # Minimum window size guard
    if h < 4 or w < 12:
      self.stdscr.addstr(0, 0, "Terminal too small")
      self.stdscr.refresh()
      return

    gutter_width = 7  # Line number gutter ("1234 │ ")
    text_width = max(1, w - gutter_width)
    text_height = max(1, h - 2)

    self.scroll_viewport(text_height, text_width)

    # 1. Header Bar
    header = f" KOBI EDITOR — {self.filename}"
    self.stdscr.attron(curses.color_pair(1) | curses.A_BOLD)
    self.stdscr.addstr(0, 0, header.ljust(w - 1)[: w - 1])
    self.stdscr.attroff(curses.color_pair(1) | curses.A_BOLD)

    # 2. Bounded Text Content & Gutter Line
    for idx in range(text_height):
      line_idx = self.row_offset + idx
      row_y = idx + 1

      if line_idx < len(self.lines):
        # Line number
        num_str = f"{line_idx + 1:>4} │ "
        self.stdscr.attron(curses.color_pair(3))
        self.stdscr.addstr(row_y, 0, num_str[:gutter_width])
        self.stdscr.attroff(curses.color_pair(3))

        # Truncate strictly to viewport width so text never writes outside the editor box
        line_content = self.lines[line_idx][
            self.col_offset : self.col_offset + text_width
        ]
        self.stdscr.addstr(row_y, gutter_width, line_content[:text_width])
      else:
        self.stdscr.attron(curses.color_pair(3))
        self.stdscr.addstr(row_y, 0, "   ~ │ ")
        self.stdscr.attroff(curses.color_pair(3))

    # 3. Status Footer Bar
    pos_info = f"Ln {self.cy + 1}, Col {self.cx + 1}"
    shortcuts = "^S: Save  |  ^F: Find  |  ^Q: Exit"
    status_line = f" {self.status:<18} {shortcuts} | {pos_info} "

    self.stdscr.attron(curses.color_pair(2))
    self.stdscr.addstr(h - 1, 0, status_line.ljust(w - 1)[: w - 1])
    self.stdscr.attroff(curses.color_pair(2))

    # Strict cursor positioning within GUI bounds
    screen_y = max(1, min(h - 2, self.cy - self.row_offset + 1))
    screen_x = max(
        gutter_width, min(w - 1, self.cx - self.col_offset + gutter_width)
    )
    self.stdscr.move(screen_y, screen_x)
    self.stdscr.refresh()

  def run(self):
    while True:
      # Clamp cursor to current line length bounds
      self.cx = max(0, min(self.cx, len(self.lines[self.cy])))
      self.render()

      try:
        ch = self.stdscr.getch()
      except KeyboardInterrupt:
        continue

      # --- SHORTCUTS ---
      if ch == 17:  # Ctrl + Q: Quit
        break
      elif ch == 19:  # Ctrl + S: Save
        self.save_file()
      elif ch == 6:  # Ctrl + F: Find / Search
        self.search()

      # --- NAVIGATION ---
      elif ch == curses.KEY_UP:
        if self.cy > 0:
          self.cy -= 1
      elif ch == curses.KEY_DOWN:
        if self.cy < len(self.lines) - 1:
          self.cy += 1
      elif ch == curses.KEY_LEFT:
        if self.cx > 0:
          self.cx -= 1
        elif self.cy > 0:
          self.cy -= 1
          self.cx = len(self.lines[self.cy])
      elif ch == curses.KEY_RIGHT:
        if self.cx < len(self.lines[self.cy]):
          self.cx += 1
        elif self.cy < len(self.lines) - 1:
          self.cy += 1
          self.cx = 0

      # --- EDITING ---
      elif ch in (curses.KEY_ENTER, 10, 13):
        current_line = self.lines[self.cy]
        self.lines[self.cy] = current_line[: self.cx]
        self.lines.insert(self.cy + 1, current_line[self.cx :])
        self.cy += 1
        self.cx = 0
      elif ch in (curses.KEY_BACKSPACE, 127, 8):
        if self.cx > 0:
          line = self.lines[self.cy]
          self.lines[self.cy] = line[: self.cx - 1] + line[self.cx :]
          self.cx -= 1
        elif self.cy > 0:
          prev_len = len(self.lines[self.cy - 1])
          self.lines[self.cy - 1] += self.lines[self.cy]
          del self.lines[self.cy]
          self.cy -= 1
          self.cx = prev_len
      elif 32 <= ch <= 126:
        line = self.lines[self.cy]
        self.lines[self.cy] = line[: self.cx] + chr(ch) + line[self.cx :]
        self.cx += 1


def main():
  filename = sys.argv[1] if len(sys.argv) > 1 else "untitled.txt"

  fd = sys.stdin.fileno()
  old_settings = termios.tcgetattr(fd)
  try:
    tty.setraw(fd)
    curses.wrapper(lambda stdscr: KobiEditor(stdscr, filename).run())
  finally:
    termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)


if __name__ == "__main__":
  main()
EOF

chmod +x "${INSTALL_PATH}"

# Keep a local executable copy named kobi.py
cp "${INSTALL_PATH}" ./kobi.py
chmod +x ./kobi.py

echo "Installation complete!"
echo "You can now run Kobi using any of these commands:"
echo "  1) kobi <file_path>"
echo "  2) python3 kobi.py <file_path>"
echo "  3) ./kobi.py <file_path>"
