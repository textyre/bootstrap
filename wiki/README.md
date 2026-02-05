# Bootstrap Wiki

This directory contains GitHub Wiki pages for the Arch Linux Workstation Bootstrap project.

## Files Created

Total: 16 wiki pages (240 KB)

### Main Pages
- **Home.md** (4.4 KB) — Main landing page with project overview
- **_Sidebar.md** (430 B) — Navigation sidebar

### Installation & Setup
- **Quick-Start.md** (4.3 KB) — Getting started guide
- **Requirements.md** (3.2 KB) — System requirements
- **Usage.md** (2.3 KB) — Usage instructions

### Components & Configuration
- **Ansible-Overview.md** (5.4 KB) — Ansible roles and architecture
- **Ansible-Decisions.md** (4.7 KB) — Architecture decision log
- **Chezmoi-Guide.md** (2.7 KB) — Dotfiles management with chezmoi
- **SSH-Setup.md** (7.5 KB) — SSH configuration (Windows → Arch)
- **Windows-Setup.md** (8.5 KB) — Windows utilities setup

### GUI Configuration
- **Xorg-Configuration.md** (9.8 KB) — X11/Xorg setup (consolidated from 4 files)
- **Display-Setup.md** (7.7 KB) — LightDM and display config (consolidated from 4 files)
- **Polybar-Architecture.md** (7.2 KB) — Polybar deep dive (summarized from 6 files)

### Migration & Future
- **Ewwii-Migration.md** (5.7 KB) — Migration plan from Polybar to Ewwii
- **Roadmap.md** (4.1 KB) — Future plans for Ansible roles

### Support
- **Troubleshooting.md** (7.2 KB) — Consolidated troubleshooting (merged 8 files)

## How to Deploy to GitHub Wiki

### Option 1: Manual Copy

1. Go to your repository's Wiki tab on GitHub
2. Create new pages with the same names
3. Copy content from each .md file
4. Save each page

### Option 2: Git Clone (if Wiki is a Git repo)

```bash
# Clone the wiki repository
git clone https://github.com/YOUR_USERNAME/bootstrap.wiki.git

# Copy all files
cp wiki/*.md bootstrap.wiki/

# Commit and push
cd bootstrap.wiki
git add .
git commit -m "Initial wiki pages"
git push
```

### Option 3: Using gh CLI

```bash
# For each file
gh wiki create "Home" < wiki/Home.md
gh wiki create "Quick-Start" < wiki/Quick-Start.md
# ... etc
```

## Content Sources

All content was consolidated from existing documentation:
- Root: README.md, REQUIREMENTS.md, USAGE.md
- docs/: QUICKSTART.md, CHEZMOI_GUIDE.md, SSH_SYNC_SCRIPTS_ANALYSIS.md
- docs/xorg/: 4 files merged into Xorg-Configuration.md
- docs/gui/display/: 4 files merged into Display-Setup.md
- docs/SubAgent docs/: 6 Polybar files summarized into Polybar-Architecture.md
- docs/plans/: POLYBAR_TO_EWWII_MIGRATION.md → Ewwii-Migration.md
- docs/roadmap/: ansible-roles.md → Roadmap.md
- docs/troubleshooting/: 8 files merged into Troubleshooting.md
- ansible/: README.md, decisions.md → Ansible pages
- windows/: README.md, ssh/README.md → Windows-Setup.md, SSH-Setup.md

## Content Guidelines

- All internal links use GitHub Wiki format: `[[Page Name]]`
- Navigation breadcrumbs: "Назад к [[Home]]" at bottom of pages
- Content in original language (mostly Russian, some English)
- File-path references adapted for wiki context
- Consolidated pages organized by topic with clear sections

## Maintenance

When updating documentation:
1. Update source files in docs/
2. Regenerate wiki pages from updated sources
3. Deploy to GitHub Wiki

---

Created: 2026-02-05
