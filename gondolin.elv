prompt-segments-defaults = [ su dir git-branch git-combined ]
rprompt-segments-defaults = [ ]

use re

use github.com/muesli/elvish-libs/git

prompt-segments = $prompt-segments-defaults
rprompt-segments = $rprompt-segments-defaults

default-glyphs = [
  &git-branch=    "⎇"
  &git-dirty=     "⊙"
  &git-ahead=     "⊕"
  &git-behind=    "∴"
  &git-deleted=   "-"
  &git-staged=    "Ξ"
  &git-untracked= "⊖"
  &git-deleted=   "⊗"
]

default-segment-style = [
  &git-branch=    [ green  ]
  &git-dirty=     [ red    ]
  &git-ahead=     [ blue   ]
  &git-behind=    [ cyan   ]
  &git-staged=    [ yellow ]
  &git-untracked= [ white  ]
  &git-deleted=   [ red    ]
  &git-combined=  [ green  ]
  &timestamp=     [ white  ]
]

glyph = [&]
segment-style = [&]

prompt-pwd-dir-length = 1

timestamp-format = "%R"

root-id = 0

bold-prompt = $false

fn -session-color {
  valid-colors = [ black red green yellow blue magenta cyan lightgray gray lightred lightgreen lightyellow lightblue lightmagenta lightcyan white ]
  put $valid-colors[(% $pid (count $valid-colors))]
}

fn -colorized [what @color]{
  if (and (not-eq $color []) (eq (kind-of $color[0]) list)) {
    color = [(explode $color[0])]
  }
  if (and (not-eq $color [default]) (not-eq $color [])) {
    if (eq $color [session]) {
      color = [(-session-color)]
    }
    if $bold-prompt {
      color = [ $@color bold ]
    }
    styled $what $@color
  } else {
    put $what
  }
}

fn -glyph [segment-name]{
  if (has-key $glyph $segment-name) {
    put $glyph[$segment-name]
  } else {
    put $default-glyphs[$segment-name]
  }
}

fn -segment-style [segment-name]{
  if (has-key $segment-style $segment-name) {
    put $segment-style[$segment-name]
  } else {
    put $default-segment-style[$segment-name]
  }
}

fn -colorized-glyph [segment-name @extra-text]{
  -colorized (-glyph $segment-name)(joins "" $extra-text) (-segment-style $segment-name)
}

fn prompt-segment [segment-or-style @texts]{
  style = $segment-or-style
  if (has-key $default-segment-style $segment-or-style) {
    style = (-segment-style $segment-or-style)
  }
  if (has-key $default-glyphs $segment-or-style) {
    texts = [ (-glyph $segment-or-style) $@texts ]
  }
  text = "["(joins ' ' $texts)"]"
  -colorized $text $style
}

segment = [&]

last-status = [&]

fn -any-staged {
  count [(each [k]{
        explode $last-status[$k]
  } [staged-modified staged-deleted staged-added renamed copied])]
}

fn -parse-git {
  last-status = (git:status)
  last-status[any-staged] = (-any-staged)
}

segment[git-branch] = {
  branch = $last-status[branch-name]
  if (not-eq $branch "") {
    if (eq $branch '(detached)') {
      branch = $last-status[branch-oid][0:7]
    }
    prompt-segment git-branch $branch
  }
}

fn -show-git-indicator [segment]{
  status-name = [
    &git-dirty=  local-modified  &git-staged=    any-staged
    &git-ahead=  rev-ahead       &git-untracked= untracked
    &git-behind= rev-behind      &git-deleted=   local-deleted
  ]
  value = $last-status[$status-name[$segment]]
  # The indicator must show if the element is >0 or a non-empty list
  if (eq (kind-of $value) list) {
    not-eq $value []
  } else {
    > $value 0
  }
}

fn -git-prompt-segment [segment]{
  if (-show-git-indicator $segment) {
    prompt-segment $segment
  }
}

-git-indicator-segments = [untracked deleted dirty staged ahead behind]

each [ind]{
  segment[git-$ind] = { -git-prompt-segment git-$ind }
} $-git-indicator-segments

segment[git-combined] = {
  indicators = [(each [ind]{
        if (-show-git-indicator git-$ind) { -colorized-glyph git-$ind }
  } $-git-indicator-segments)]
  if (> (count $indicators) 0) {
    color = (-segment-style git-combined)
    put (-colorized '[' $color) $@indicators (-colorized ']' $color)
  }
}

fn -prompt-pwd {
  tmp = (tilde-abbr $pwd)
  if (== $prompt-pwd-dir-length 0) {
    put $tmp
  } else {
    re:replace '(\.?[^/]{'$prompt-pwd-dir-length'})[^/]*/' '$1/' $tmp
  }
}

segment[dir] = {
  prompt-segment dir (-prompt-pwd)
}

segment[su] = {
  uid = (id -u)
  if (eq $uid $root-id) {
    prompt-segment su
  }
}

segment[timestamp] = {
  prompt-segment timestamp (date +$timestamp-format)
}

segment[session] = {
  prompt-segment session
}

segment[arrow] = {
  -colorized-glyph arrow " "
}

fn -interpret-segment [seg]{
  k = (kind-of $seg)
  if (eq $k 'fn') {
    # If it's a lambda, run it
    $seg
  } elif (eq $k 'string') {
    if (has-key $segment $seg) {
      # If it's the name of a built-in segment, run its function
      $segment[$seg]
    } else {
      # If it's any other string, return it as-is
      put $seg
    }
  } elif (or (eq $k 'styled') (eq $k 'styled-text')) {
    # If it's a styled object, return it as-is
    put $seg
  }
}

fn -build-chain [segments]{
  if (eq $segments []) {
    return
  }
  first = $true
  output = ""
  -parse-git
  for seg $segments {
    time = (-time { output = [(-interpret-segment $seg)] })
    if (> (count $output) 0) {
      if (not $first) {
        -colorized-glyph chain
      }
      put $@output
      first = $false
    }
  }
}

fn prompt {
  if (not-eq $prompt-segments []) {
    put (-build-chain $prompt-segments)
  }
}

fn rprompt {
  if (not-eq $rprompt-segments []) {
    put (-build-chain $rprompt-segments)
  }
}

fn init {
  edit:prompt = $prompt~
  edit:rprompt = $rprompt~
}

init

summary-repos = []

fn summary-status {
  prev = $pwd
  each $echo~ $summary-repos | sort | each [r]{
    cd $r
    -parse-git
    status = [($segment[git-combined])]
    if (eq $status []) {
      status = [(-colorized "[" session) (styled OK green) (-colorized "]" session)]
    }
    status = [$@status ($segment[git-branch])]
    echo $@status (styled (tilde-abbr $r) blue)
  }
  cd $prev
}

