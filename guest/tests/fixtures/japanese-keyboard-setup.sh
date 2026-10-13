# The setup form: every question Omarchy asks a human to describe their machine
# — keyboard, account, hostname, timezone — plus the rules those answers are
# checked against. Shared by the two places that ask them: the ISO
# configurator's user step and this package's first-boot owner setup
# (omarchy-provision-owner). Sourced by both, so the copies cannot drift the way
# the keyboard list already did.
#
# Every prompt reports one of three statuses, and both callers read them the
# same way:
#
#   0    field is set, move on
#   1    Esc — unwind to the start of the form
#   130  Ctrl+C — a per-caller side channel (the installer arms deferred
#        provisioning or toggles encryption; first-boot setup offers a reboot)
#
# gum is the reason those two are the whole vocabulary: Esc and Ctrl+C are the
# only keys any gum widget exits on, and Ctrl+C arrives as a byte in raw mode,
# so it never reaches the shell as SIGINT. Act on the status, never on a trap.
#
# Callers supply `notice <message> <seconds>` for validation feedback, and set
# the variables these prompts write: keyboard, keyboard_label, username,
# password, password_confirmation, full_name, email_address, hostname, timezone.

OMARCHY_FORM_BACK=1
OMARCHY_FORM_SIGNAL=130

# The English layouts lead, then everything else alphabetically. gum choose
# paginates in --height-sized pages and jumps to the page holding --selected,
# so an alphabetical English (US) landed deep enough to sit alone at the edge
# of a page of layouts nobody scanning for it reads. Up here the default and
# its variants are the first thing on screen no matter how the list grows.
OMARCHY_KEYBOARD_LAYOUTS=$'English (US)|us
English (UK)|uk
English (US, Dvorak)|dvorak
English (US, Colemak)|colemak
Azerbaijani|azerty
Belarusian|by
Belgian|be-latin1
Bulgarian|bg-cp1251
Croatian|croat
Czech|cz
Danish|dk-latin1
Dutch|nl
Estonian|et
Finnish|fi
French|fr
French (Canada)|cf
French (Switzerland)|fr_CH
Georgian|ge
German|de
German (Switzerland)|de_CH-latin1
Greek|gr
Hebrew|il
Hungarian|hu
Icelandic|is-latin1
Irish|ie
Italian|it
Japanese|jp106
Kazakh|kazakh
Kyrgyz|kyrgyz
Lao|la-latin1
Latvian|lv
Lithuanian|lt
Macedonian|mk-utf
Norwegian|no-latin1
Polish|pl
Portuguese|pt-latin1
Portuguese (Brazil)|br-abnt2
Romanian|ro
Russian|ru
Serbian|sr-latin
Slovak|sk-qwertz
Slovenian|slovene
Spanish|es
Spanish (Latin American)|la-latin1
Swedish|sv-latin1
Tajik|tj_alt-UTF8
Turkish|trq
Ukrainian|ua'

OMARCHY_USERNAME_PATTERN='^[a-z_][a-z0-9_-]*[$]?$'
OMARCHY_RESERVED_USERNAMES='^(root|bin|daemon|mail|ftp|http|nobody|dbus|systemd-coredump|systemd-network|systemd-oom|systemd-journal-remote|systemd-resolve|systemd-timesync|tss|uuidd|alpm|git|avahi|cups|cups-browsed|lp|_talkd|polkitd|rtkit|qemu|brltty|gluster|rpc|libvirt-qemu|pcscd|nvidia-persistenced|sddm)$'
OMARCHY_HOSTNAME_PATTERN='^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$'
OMARCHY_HOSTNAME_DEFAULT='omarchy'

# Installer targets are empty, so any account is fair game; first-boot setup
# overrides this because its machine already has users.
omarchy_username_taken() { return 1; }

# `x=$(gum ...) && status=0 || status=$?` rather than a bare assignment followed
# by `status=$?`: one caller runs under `set -e`, where a cancelled prompt is a
# failing assignment that would kill the script before the status is read.

omarchy_prompt_keyboard() {
  local choice status
  choice=$(printf '%s\n' "$OMARCHY_KEYBOARD_LAYOUTS" | cut -d'|' -f1 |
    gum choose --height 10 --selected "English (US)" --header "Select keyboard layout") && status=0 || status=$?
  ((status == 0)) || return $status

  keyboard_label="$choice"
  keyboard=$(printf '%s\n' "$OMARCHY_KEYBOARD_LAYOUTS" | awk -F'|' -v c="$choice" '$1==c{print $2; exit}')
}
