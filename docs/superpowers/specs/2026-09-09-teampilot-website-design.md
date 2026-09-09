# TeamPilot Website Design Specification

**Date:** 2026-09-09
**Status:** Approved by user
**Reference:** https://www.onorca.dev/

## Goal

Create a polished, bilingual, GitHub Pages-ready marketing website for TeamPilot. The site should use Orca's product-storytelling rhythm as inspiration while maintaining TeamPilot's own brand, truthful product claims, and reusable architecture for future documentation, changelogs, and blog content.

## Scope

The first release includes:

- An English-first landing page at `/`.
- A Chinese landing page at `/zh/`.
- Feature pages at `/features/` and `/zh/features/`.
- Download pages at `/download/` and `/zh/download/`.
- Documentation hubs at `/docs/` and `/zh/docs/`.
- Changelog hubs at `/changelog/` and `/zh/changelog/`.
- Blog hubs and article routes at `/blog/`, `/zh/blog/`, `/blog/[slug]/`, and `/zh/blog/[slug]/`.
- A responsive navigation with locale switching, GitHub, and download CTAs.
- GitHub Actions deployment to GitHub Pages.

The website is a separate Astro project under `website/` and does not change the Flutter application architecture under `client/`.

## Product narrative

The site positions TeamPilot as a cross-platform agent workbench where multiple coding agents, experts, workspaces, terminals, editors, and remote machines work together.

Primary English message:

> Run every agent. Ship as a team.

Primary Chinese message:

> 让每个智能体各司其职，一起把代码交付。

Product claims must come from the repository's documented capabilities. The site must not invent user counts, performance measurements, customer logos, or testimonials. Supported CLI names, platform availability, releases, GitHub, Discord, and QQ links should point to current TeamPilot sources.

## Page architecture

### Homepage

Sections appear in this order:

1. Navigation with logo, content links, locale switcher, GitHub link, and download CTA.
2. Hero with headline, supporting copy, download/GitHub CTAs, and an HTML/CSS TeamPilot workbench mockup.
3. Capability strip for multi-CLI support, workspaces, SSH, Git, mobile, and open source.
4. Core feature narrative for multi-CLI management, expert profiles, team collaboration, and remote development.
5. Product showcase panels for Workspace, Agent Team, Git/Editor, and Mobile/SSH.
6. Supported CLI matrix using data shared with the feature and download sections.
7. Four-step workflow from prompt to shipped code.
8. Open-source and community section linking to GitHub, Discord, and QQ.
9. FAQ accordion.
10. Final download CTA and footer.

### Supporting pages

Features and download pages are hand-authored Astro pages using the same components as the homepage. Docs, changelog, and blog use Astro Content Collections so page templates remain stable while content grows.

Every content type has English and Chinese entries. The locale is represented by the route, with English unprefixed and Chinese under `/zh/`.

## Visual system

The visual direction is an “agent control room”: a dark, focused development environment with luminous operational states.

- Background: ink/navy gradients with subtle grid and noise textures.
- Primary accent: electric teal/green for links, active states, and CTAs.
- Secondary accent: warm yellow for warnings, queued work, and attention states.
- Typography: geometric sans-serif for marketing copy, monospace for terminal and code UI; Chinese uses a system fallback stack and does not require a remote font at runtime.
- Brand assets: reuse `assets/icon.svg` and create a website wordmark treatment without modifying the application icon.
- Cards: soft borders, restrained radius, layered panels, and high-contrast status dots.

The design borrows the reference site's dense product storytelling and interactive product panels, but not its copy, imagery, logos, or protected visual assets.

## Interaction requirements

- Locale switcher preserves the current content type when a translated route exists.
- Mobile navigation opens and closes with keyboard-accessible controls.
- FAQ items are semantic disclosure controls and support keyboard navigation.
- Product showcase tabs update visible content without requiring a backend.
- Download cards filter by operating system and link to GitHub Releases.
- Install command cards offer a clipboard copy action with a visible success state.
- Scroll reveal animation is lightweight and disabled or reduced when `prefers-reduced-motion` is enabled.
- All interactive controls have visible focus states and touch targets of at least 44px.

## Astro architecture

The project uses Astro static generation with TypeScript and Tailwind CSS, based on the structure and design system of the RicoFast open-source SaaS template, subject to final license verification before code import.

Planned responsibilities:

- `website/src/layouts/`: document shell, metadata, navigation, locale context, and footer.
- `website/src/components/`: reusable marketing UI such as hero, workbench mockup, feature cards, tabs, FAQ, downloads, and content cards.
- `website/src/content/`: localized Markdown or MDX collections for docs, blog, and changelog entries.
- `website/src/data/`: localized homepage copy, supported CLI data, platform downloads, FAQ entries, and community links.
- `website/src/pages/`: route-level composition only.
- `website/src/styles/`: design tokens, global styles, responsive rules, and motion utilities.
- `website/public/`: favicon, social preview image, and static public assets.
- `.github/workflows/website-pages.yml`: install, check, build, and deploy workflow.

The homepage product mockups are built from semantic HTML/CSS components rather than flattened screenshots so they remain responsive, searchable, and accessible. Existing repository screenshots may be reused only where they are accurate and have an appropriate alt description.

## SEO and GitHub Pages

- Set `site` and repository-aware `base` in Astro configuration for GitHub Pages project-site hosting.
- Generate locale-specific title, description, canonical, Open Graph, and Twitter metadata.
- Generate sitemap and robots output during the static build.
- Use relative-safe asset and navigation helpers so project-site subpaths work in production.
- Deploy through GitHub Actions with the Pages artifact and deployment actions.

## Validation

The website workflow and local checks must cover:

- Astro type/component validation.
- TypeScript validation for interactive islands.
- Production build output.
- All declared locale routes resolving during the build.
- Responsive smoke checks for desktop and mobile navigation, locale switching, FAQ, tabs, copy action, and download links.
- A production preview check to catch incorrect GitHub Pages base paths.

## Non-goals

- No backend, authentication, analytics service, CMS, or server-side rendering.
- No replacement of the Flutter app's existing documentation or release workflows.
- No invented testimonials or metrics.
- No direct reuse of Orca's proprietary assets or wording.
