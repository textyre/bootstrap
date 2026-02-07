# Picom v12.5/v13 Configuration Research

**Date:** 2026-02-07
**Focus:** Upstream picom (yshui/picom) vs picom-ftlabs fork
**Versions Researched:** v12.5, v13 (upstream), picom-ftlabs (latest)

---

## 1. New Rules Syntax (Upstream v12+)

### Basic Structure

The `rules` option defines a list of rule groups where each group applies settings to windows matching specified conditions.

```conf
rules: (
  {
    match = "condition_string";
    option1 = value1;
    option2 = value2;
  },
  {
    match = "another_condition";
    option3 = value3;
  }
)
```

### Matching Behavior

- Rules are evaluated **in order** they appear in config file
- Options are applied **cumulatively** as conditions match
- If the same option is set multiple times, **the last value wins**
- If `match` is omitted, the rule **always matches**

### Example: Focus-Based Opacity

```conf
rules: (
  {
    match = "class_g = 'URxvt' && focused";
    opacity = 0.9;
  },
  {
    match = "class_g = 'URxvt' && !focused";
    opacity = 0.6;
  }
)
```

### Example: Window Type Handling

```conf
rules: (
  { match = "window_type = 'tooltip'"; fading = false; },
  { match = "window_type = 'dock'"; blur-background = false; },
  { match = "window_type = 'notification'"; shadow = false; }
)
```

### Example: Fullscreen Corner Radius

```conf
rules = (
  { match = "fullscreen"; corner-radius = 0; }
)
```

### Condition Syntax (FORMAT OF CONDITIONS)

Conditions use a C-like expression language with:

- **Window properties:** `class_g`, `class_i`, `name`, `window_type`, `focused`, `fullscreen`, etc.
- **Logical operators:** `&&` (and), `||` (or), `!` (not)
- **Comparison:** `=` (string equality), `!=`, etc.
- **String matching:** Use quotes for literal strings

Example conditions:
```conf
class_g = 'Alacritty' && !focused
class_g = 'Firefox' || class_g = 'Chromium'
window_type = 'normal' && focused
name ~= 'Firefox'  # regex match (if supported)
```

### Per-Window Rule Options

All of these can be set per-window via rules:

| Option | Type | Purpose |
|--------|------|---------|
| `opacity` | 0.0-1.0 | Window transparency |
| `fade` | bool | Enable fading animation |
| `shadow` | bool | Draw drop shadow |
| `shadow-color` | hex/rgba | Shadow color |
| `shadow-radius` | int | Shadow blur radius |
| `corner-radius` | int | Rounded corner radius (0 = no rounding) |
| `blur-background` | bool | Enable background blur |
| `full-shadow` | bool | Full window shadow (vs frame-only) |
| `redir-ignored` | bool | Redirect ignored windows |
| `animations` | array | Animation rules (see section 2) |

---

## 2. New Animation Configuration Format (Upstream v12+)

### Architecture

Upstream picom v12+ replaces the picom-ftlabs animation system with a new, more integrated approach using **triggers** and **suppressions**.

### Basic Structure

```conf
animations = (
  {
    triggers = [ "open", "show" ];
    suppressions = [];
    preset = "slide-in";
    direction = "down";
  },
  {
    triggers = [ "close", "hide" ];
    preset = "slide-out";
    direction = "down";
  }
)
```

### Components

#### **Triggers** (Required)

List of animation trigger events. Specifies when an animation should start.

**Built-in trigger types:**
- `open` — Window opens
- `close` — Window closes
- `show` — Window becomes visible
- `hide` — Window becomes hidden
- `focus` — Window receives focus
- `unfocus` — Window loses focus
- `workspace-in` — Workspace switches in
- `workspace-out` — Workspace switches out

#### **Suppressions** (Optional, default = `[]`)

List of trigger types to suppress while this animation is running. Prevents animation interruption.

**Example:** If you want a "close" animation to complete without being interrupted by "hide":
```conf
{
  triggers = [ "close" ];
  suppressions = [ "hide" ];
  preset = "fade-out";
}
```

### Presets

Picom v12+ includes built-in animation presets:

- `slide-in` — Slide window in
- `slide-out` — Slide window out
- `fade-in` — Fade window in
- `fade-out` — Fade window out
- `appear` — Quick appearance
- `disappear` — Quick disappearance

### Preset Parameters

When using a preset, configure behavior with:

```conf
{
  triggers = [ "open" ];
  preset = "slide-in";
  direction = "down";      # Direction: up, down, left, right
  duration = 300;          # Milliseconds
  timing-function = "ease-in-out";
  # Other params vary by preset
}
```

### Full Animation Example in Rules

```conf
rules: (
  {
    match = "class_g = 'Alacritty'";
    animations = (
      {
        triggers = [ "open" ];
        preset = "slide-in";
        direction = "down";
        duration = 200;
      },
      {
        triggers = [ "close" ];
        preset = "slide-out";
        direction = "down";
        duration = 200;
      }
    );
  }
)
```

### Key Difference from ftlabs

| Feature | picom-ftlabs | Upstream v12+ |
|---------|--------------|--------------|
| Animation style | Stiffness/dampening-based (physics) | Preset + timing-function based |
| Configuration | `animation-stiffness-in-tag`, `animation-for-open-window`, etc. | `triggers`, `suppressions`, `preset` |
| Per-window animations | Via rule options | Via rule `animations` array |
| Fading interaction | Fading + animations can coexist (sometimes) | Fading has **no effect** when animations are used |

---

## 3. Differences: picom-ftlabs vs Upstream Picom

### picom-ftlabs (FT-Labs Fork)

**Repository:** [github.com/FT-Labs/picom](https://github.com/FT-Labs/picom)
**Branch:** `next`
**Package:** `picom-ftlabs-git` (AUR)

**Animation Configuration (Old Style):**
```conf
animations = (
  { triggers = [ "open" ]; preset = "slide-down"; duration = 300; },
  { triggers = [ "close" ]; preset = "slide-up"; duration = 300; }
)

# Or with physics parameters (ftlabs-specific):
animation-stiffness-in-tag = 120;
animation-dampening = 0.4;
animation-mass = 1;
animation-for-open-window = "zoom";
animation-for-unmap-window = "slide-down";
```

**Features:**
- **10+ unique animation types** (open window, tag change, fading, etc.)
- Physics-based animations (stiffness, dampening, mass parameters)
- Better per-window animation exclusion
- More granular control over animation behavior

**Status:** Actively maintained, community-driven, Arch User Repository (AUR) package available

### Upstream Picom (yshui/picom)

**Repository:** [github.com/yshui/picom](https://github.com/yshui/picom)
**Branch:** `next` (dev), `main` (stable)
**Current Stable:** v12.5 (released Nov 13, with bug fix for qtile/unfocused windows)

**Animation Configuration (New Style):**
```conf
animations = (
  {
    triggers = [ "open", "show" ];
    suppressions = [];
    preset = "slide-in";
    direction = "down";
    duration = 300;
    timing-function = "ease-in-out";
  }
)
```

**Features:**
- **Preset-based animations** (more predictable, less configuration)
- **Triggers & suppressions** system (cleaner interrupt handling)
- Integrated with standard `rules` system
- **Fading disabled when animations active** (not both simultaneously)
- Simpler mental model: no physics parameters

**Status:** Official upstream, actively maintained by yshui, now in all major distros

### Compatibility Matrix

| Feature | picom-ftlabs | Upstream v12+ |
|---------|--------------|---------------|
| Animation presets | Yes | Yes |
| Physics-based (stiffness/mass) | **YES** | **NO** |
| Per-window rules | Yes | Yes |
| Window-type specific animations | Yes | Yes |
| Focus/unfocus triggers | Yes | Yes |
| Workspace switch animations | Partial | Yes (`workspace-in/out`) |
| Fading + animations together | Sometimes | **NO** (animations take priority) |
| Custom animation scripting | Advanced | Limited (presets + timing functions) |

---

## 4. Options NOT Supported in Upstream (vs ftlabs)

These **picom-ftlabs-specific** options have **no equivalent** in upstream v12+:

```conf
# OLD FTLABS SYNTAX (NOT IN UPSTREAM):
animation-stiffness-in-tag = 120;
animation-dampening = 0.4;
animation-clamping = false;
animation-mass = 1;
animation-for-open-window = "zoom";
animation-for-unmap-window = "slide-down";
animation-for-transient-window = "slide-down";
```

**Migration path for ftlabs users:**
1. Replace physics parameters (stiffness/dampening) with single `duration` + `timing-function`
2. Replace `animation-for-*` with `rules` + `animations` array with appropriate `triggers`
3. Use built-in presets instead of custom animation definitions
4. Accept that fading must be disabled to use animations

---

## 5. Sample Configuration Structure (Upstream)

Full example showing best practices:

```conf
# Backend and rendering
backend = "glx";
glx-no-stencil = true;
use-damage = true;
vsync = true;

# Shadows
shadow = true;
shadow-radius = 7;
shadow-opacity = 0.4;
shadow-offset-x = -7;
shadow-offset-y = -7;
shadow-exclude = [
  "window_type = 'dock'",
  "window_type = 'desktop'"
];

# Fading (disabled if using animations)
fading = false;
fade-in-step = 0.03;
fade-out-step = 0.03;

# Transparency
frame-opacity = 0.7;
inactive-opacity = 0.8;
active-opacity = 1.0;

# Corners
corner-radius = 10;
detect-rounded-corners = true;

# Blur
blur-background = true;
blur-method = "gaussian";
blur-size = 10;
blur-deviation = 3.0;

# Animations (new v12+ system)
animations = (
  {
    triggers = [ "open", "show" ];
    preset = "slide-in";
    direction = "down";
    duration = 300;
    timing-function = "ease-in-out";
  },
  {
    triggers = [ "close", "hide" ];
    preset = "slide-out";
    direction = "up";
    duration = 300;
  }
)

# Window rules with per-window settings
rules: (
  {
    match = "class_g = 'Alacritty'";
    opacity = 0.95;
    corner-radius = 8;
    shadow = true;
  },
  {
    match = "window_type = 'tooltip'";
    shadow = false;
    opacity = 0.95;
  },
  {
    match = "window_type = 'notification'";
    fade = false;
    shadow = false;
  },
  {
    match = "class_g = 'Firefox' && focused";
    opacity = 1.0;
  },
  {
    match = "class_g = 'Firefox' && !focused";
    opacity = 0.85;
  }
)
```

---

## 6. Migration Guide: ftlabs → Upstream

If you're moving from picom-ftlabs to upstream picom v12+:

### Step 1: Remove Physics-Based Animation Config

**OLD (ftlabs):**
```conf
animation-stiffness-in-tag = 120;
animation-dampening = 0.4;
animation-mass = 1;
animation-clamping = false;
```

**NEW (upstream):**
```conf
# Remove entirely — use timing-function instead
animations = (
  { triggers = [ "open" ]; preset = "slide-in"; timing-function = "ease-in-out"; }
)
```

### Step 2: Replace Animation Triggers

**OLD (ftlabs):**
```conf
animation-for-open-window = "zoom";
animation-for-unmap-window = "slide-down";
animation-for-transient-window = "slide-down";
```

**NEW (upstream):**
```conf
rules: (
  {
    match = "window_type = 'normal'";
    animations = (
      { triggers = [ "open", "show" ]; preset = "slide-in"; direction = "down"; }
    );
  }
)
```

### Step 3: Handle Fading Conflict

**Important:** Fading has **no effect** when animations are enabled in upstream.

**OLD (ftlabs, could mix):**
```conf
fading = true;
animations = (...);
```

**NEW (upstream, choose one):**
```conf
# Option A: Use animations only
fading = false;
animations = (...);

# Option B: Use fading only
fading = true;
animations = ();
```

### Step 4: Test Window-Type Rules

Use upstream's trigger system for window-type specific behavior:

```conf
rules: (
  {
    match = "window_type = 'tooltip'";
    animations = ();  # No animations for tooltips
  },
  {
    match = "window_type = 'normal' && focused";
    animations = (
      { triggers = [ "focus" ]; preset = "appear"; }
    );
  }
)
```

---

## 7. Key Learning Points

1. **Rules are the foundation** — All per-window effects use the unified `rules` system
2. **Animations integrated by default** — v12+ has animations as first-class feature, not a fork-only addition
3. **No more physics parameters** — Upstream uses timing functions; ftlabs uses stiffness/dampening
4. **Fading vs Animations** — Can't have both active; animations take priority
5. **Suppressions prevent interruption** — Use when you need animations to complete without being cut short
6. **Presets are limited but stable** — ~6 built-in presets; more flexibility via timing functions but no custom animation scripting
7. **Trigger system is powerful** — Can react to focus, workspace, open/close, etc.

---

## 8. References & Sources

- [Picom Official Documentation](https://picom.app/)
- [Picom v12.5 Release Notes](https://github.com/yshui/picom/releases/tag/v12.5) (Nov 13)
- [Picom Sample Configuration](https://github.com/yshui/picom/blob/next/picom.sample.conf)
- [Picom Issues #1372: Need help testing animations](https://github.com/yshui/picom/discussions/1372)
- [Picom Issues #1380: Exclude animation for specific window types](https://github.com/yshui/picom/issues/1380)
- [FT-Labs Picom Fork](https://github.com/FT-Labs/picom)
- [AUR: picom-ftlabs-git](https://aur.archlinux.org/packages/picom-ftlabs-git)
- [ArchWiki: Picom](https://wiki.archlinux.org/title/Picom)
- [Debian Manpages: picom(1)](https://manpages.debian.org/testing/picom/picom.1.en.html)

---

## Summary Table: Config Syntax Comparison

| Aspect | picom-ftlabs | Upstream v12+ |
|--------|--------------|---------------|
| **Animation entry point** | Global + rules | Global array + per-rule |
| **Physics config** | `animation-stiffness-*`, `animation-dampening` | `timing-function`, `duration` |
| **Trigger syntax** | Event names | `triggers = [ ... ]` array |
| **Suppressions** | Implicit (sometimes breaks) | Explicit `suppressions = [ ... ]` |
| **Window rules** | Yes | Yes (unified `rules:` block) |
| **Fading + animations** | Partial coexistence | Mutually exclusive |
| **Custom animation scripts** | Advanced capability | Presets + timing functions only |
| **Upstream integration** | Maintained by community | Official, in all major distros |

