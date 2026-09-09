# TeamPilot Website Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox ( - [ ] ) syntax for tracking.

**Goal:** Build and deploy a polished English-first, Chinese-localized TeamPilot marketing site with home, features, download, docs, changelog, blog, SEO, and GitHub Pages support.

**Architecture:** Create an isolated Astro project in website/, starting from the MIT-licensed RicoFast Astro 6/Tailwind 4 template. Keep copy and repeatable product facts in typed data/content collections, compose pages from small Astro components, and use tiny client-side scripts for tabs, locale/mobile navigation, FAQ, platform filters, copy buttons, and reveal animation.

**Tech Stack:** Astro 6, TypeScript, Tailwind CSS v4, Astro Content Layer/MDX, @astrojs/sitemap, @astrojs/rss, Lucide Astro icons, pnpm 9+, Node 22+.

## Global Constraints

- The website is a separate Astro project under website/ and does not change the Flutter application architecture under client/.
- An English-first landing page is at /; the Chinese version is at /zh/.
- Supporting pages exist at /features/, /download/, /docs/, /changelog/, /blog/ and matching /zh/ routes.
- Product claims must come from the repository's documented capabilities.
- The site must not invent user counts, performance measurements, customer logos, or testimonials.
- The design borrows the reference site's dense product storytelling and interactive product panels, but not its copy, imagery, logos, or protected visual assets.
- Homepage product mockups are semantic HTML/CSS components, not flattened screenshots.
- The primary accent is electric teal/green; the secondary accent is warm yellow.
- Chinese uses a system fallback stack and does not require a remote font at runtime.
- Locale switching preserves the current content type when a translated route exists.
- All interactive controls have visible focus states and touch targets of at least 44px.
- Scroll reveal animation is disabled or reduced when prefers-reduced-motion is enabled.
- The build is static and has no backend, authentication, analytics service, CMS, or server-side rendering.
- GitHub Pages deployment uses a GitHub Actions Pages artifact and deployment workflow.
- Existing dirty submodule changes under client/ must not be staged by website commits.

---

## File map

- website/package.json, website/pnpm-lock.yaml, website/astro.config.mjs, website/tsconfig.json: toolchain and Pages-aware build configuration.
- website/src/layouts/: document shell, metadata, navigation, footer, and article layout.
- website/src/components/: reusable marketing UI and semantic HTML/CSS product mockups.
- website/src/data/: localized navigation, homepage copy, CLI/platform facts, FAQs, community links, and download links.
- website/src/content.config.ts and website/src/content/: typed localized docs, blog, and changelog content.
- website/src/pages/: route-level composition for English and Chinese pages.
- website/src/lib/: locale/path helpers and site URL helpers.
- website/src/styles/: brand tokens, typography, grid background, motion, and responsive rules.
- website/public/: favicon, copied TeamPilot icon, OG image, robots, and public static assets.
- website/scripts/check-build.mjs: dependency-free built-output smoke test.
- .github/workflows/website-pages.yml: website-only CI and GitHub Pages deployment.

## Task 1: Bootstrap from RicoFast

**Files:**

- Create: website/package.json, website/pnpm-lock.yaml, website/astro.config.mjs, website/tsconfig.json
- Create: the template's website/src/assets/js/main.js, website/src/collections/menu.json, website/src/collections/social.json, website/src/collections/stack.json, website/src/config/site.js, website/src/content.config.js, website/src/layouts/Layout.astro, website/src/layouts/Meta.astro, website/src/layouts/PageLayout.astro, website/src/layouts/PostLayout.astro, website/src/pages/index.astro, website/src/pages/features.astro, website/src/pages/blog/index.astro, website/src/pages/blog/[...slug].astro, website/src/pages/changelog.astro, website/src/pages/404.astro, website/src/styles/global.css, and the template's public assets
- Create: website/LICENSE.template and website/scripts/check-build.mjs

**Interfaces:**

- Consumes: https://github.com/ricocc/ricoui-saas-template.git, the approved design specification, and assets/icon.svg.
- Produces: a standalone website package with pnpm build, pnpm check, pnpm preview, and pnpm smoke scripts.

- [ ] Step 1: Clone to a temporary directory and verify the upstream MIT metadata.

~~~
template_tmp=$(mktemp -d /tmp/teampilot-website-template.XXXXXX)
git clone --depth 1 https://github.com/ricocc/ricoui-saas-template.git "$template_tmp/ricofast"
rg -n '"license": "MIT"|Astro 6|Tailwind CSS v4' "$template_tmp/ricofast/package.json" "$template_tmp/ricofast/README.md"
~~~

- [ ] Step 2: Copy the source without the nested repository or build output.

~~~
mkdir -p website
rsync -a --exclude node_modules --exclude dist --exclude .git "$template_tmp/ricofast/" website/
~~~

- [ ] Step 3: Rename the package, mark it private, preserve Astro/MDX/sitemap/RSS/Tailwind dependencies, and set scripts to:

~~~
"scripts": {
  "dev": "astro dev",
  "build": "astro check && astro build",
  "check": "astro check",
  "preview": "astro preview",
  "smoke": "node scripts/check-build.mjs"
}
~~~

Keep Node >=22.12.0 and pnpm >=9. Copy the upstream MIT notice and repository URL to website/LICENSE.template.

- [ ] Step 4: Create website/scripts/check-build.mjs with required output checks:

~~~
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
const root = new URL('../dist/', import.meta.url).pathname;
const required = ['index.html', 'zh/index.html', '404.html', 'sitemap-index.xml'];
for (const file of required) {
  const path = join(root, file);
  if (!existsSync(path)) throw new Error('Missing built output: ' + file);
}
const html = readFileSync(join(root, 'index.html'), 'utf8');
if (!html.includes('TeamPilot')) throw new Error('Missing TeamPilot homepage');
if (!html.includes('lang="en"')) throw new Error('Missing English lang attribute');
console.log('Website smoke check passed for ' + required.length + ' outputs.');
~~~

- [ ] Step 5: Verify and commit the bootstrap.

~~~
cd website
pnpm install --frozen-lockfile
pnpm build
git add website
git commit -m "feat(website): bootstrap Astro marketing site"
~~~

## Task 2: Add brand system, locale utilities, and shell

**Files:**

- Modify: website/astro.config.mjs, website/src/styles/global.css
- Replace: website/src/layouts/Layout.astro, website/src/components/sections/Header.astro, website/src/components/sections/Footer.astro
- Create: website/src/layouts/SiteLayout.astro, website/src/data/site.ts, website/src/lib/locale.ts, website/src/lib/urls.ts
- Create: website/public/favicon.svg, website/public/brand-icon.svg

**Interfaces:**

- Consumes: Task 1 and assets/icon.svg.
- Produces: SiteLayout props { title, description, locale, pathname, image? }, localePath(pathname, locale), and switchLocalePath(pathname, locale).

- [ ] Step 1: Implement Locale = 'en' | 'zh', defaultLocale = 'en', localePrefix, localePath, and switchLocalePath. Verify these exact mappings:

~~~
localePath('/features/', 'en') === '/features/'
localePath('/features/', 'zh') === '/zh/features/'
localePath('/zh/features/', 'en') === '/features/'
localePath('/zh/features/', 'zh') === '/zh/features/'
~~~

- [ ] Step 2: Create typed site data exporting siteConfig, navItems, communityLinks, supportedClis, and downloadTargets. Use the repository's current links:

~~~
githubUrl: 'https://github.com/hhoao/teampilot'
releasesUrl: 'https://github.com/hhoao/teampilot/releases'
discordUrl: 'https://discord.com/channels/1518523215767666719/1518523216912449669'
qqUrl: 'https://qm.qq.com/q/ScSC18EPaE'
~~~

- [ ] Step 3: Configure site from PUBLIC_SITE_URL, base from PUBLIC_BASE_PATH, local base /, keep the Tailwind Vite plugin, and keep MDX/sitemap integrations.

- [ ] Step 4: Replace the shell. Header has semantic nav, icon/wordmark, locale switcher, mobile menu with aria-expanded, GitHub link, and Download CTA. Footer has Product, Resources, Community, License, current year, and upstream attribution.

- [ ] Step 5: Replace template styles with ink/navy backgrounds, teal accent, warm yellow state, panel borders, monospace code, grid texture, focus rings, responsive containers, and reduced-motion rules. Remove remote Google Font imports.

- [ ] Step 6: Run pnpm check, pnpm build, pnpm smoke; commit with:

~~~
git add website
git commit -m "feat(website): add bilingual TeamPilot shell"
~~~

## Task 3: Build the bilingual homepage

**Files:**

- Create: website/src/data/home.ts
- Create: website/src/components/home/HeroSection.astro, website/src/components/home/CapabilityStrip.astro, website/src/components/home/WorkbenchMockup.astro, website/src/components/home/FeatureNarrative.astro, website/src/components/home/ProductShowcase.astro, website/src/components/home/WorkflowSteps.astro, website/src/components/home/CommunitySection.astro, website/src/components/home/FaqSection.astro
- Replace: website/src/pages/index.astro
- Create: website/src/pages/zh/index.astro
- Modify: website/src/styles/global.css

**Interfaces:**

- Consumes: SiteLayout, siteConfig, locale data, and shared UI primitives.
- Produces: English and Chinese homepages with the ten approved sections.

- [ ] Step 1: Add typed HomeCopy for en and zh: hero, capability labels, four core features, four showcase tabs, four workflow steps, community copy, and FAQ. Use facts from README.md only.

- [ ] Step 2: Implement WorkbenchMockup as selectable semantic HTML with window chrome, file tree, three agent status rows, terminal, diff/editor panel, text status labels, aria-label, and responsive collapse below 720px.

- [ ] Step 3: Implement Hero, capability strip, feature narrative, showcase, workflow, community, and FAQ as focused components. FAQ uses details/summary or an equivalent keyboard-accessible disclosure.

- [ ] Step 4: Compose both route files from the same components and locale data. Do not duplicate component markup solely for translation.

- [ ] Step 5: Add mobile-first CSS and verify 375px, 768px, and 1440px layouts have no horizontal scroll.

- [ ] Step 6: Run pnpm check, pnpm build, pnpm smoke; commit:

~~~
git add website/src/data/home.ts website/src/components/home website/src/pages/index.astro website/src/pages/zh/index.astro website/src/styles/global.css
git commit -m "feat(website): add bilingual TeamPilot homepage"
~~~

## Task 4: Add Features, Download, and client-side interactions

**Files:**

- Create: website/src/data/features.ts, website/src/data/downloads.ts
- Create: website/src/components/features/FeatureGrid.astro, website/src/components/features/CapabilityMatrix.astro
- Create: website/src/components/download/DownloadCards.astro, website/src/components/download/InstallCommand.astro
- Create: website/src/scripts/site-interactions.ts
- Create: website/src/pages/features.astro, website/src/pages/zh/features.astro
- Create: website/src/pages/download.astro, website/src/pages/zh/download.astro

**Interfaces:**

- Consumes: supportedClis, downloadTargets, locale helpers, and shared shell.
- Produces: platform-aware cards, shared CLI matrix, tabbed feature panels, and command-copy behavior.

- [ ] Step 1: Define typed records for multi-CLI abstraction, experts, teams, remote SSH, workspace/IDE, Git, mobile, and extensibility. Download records have platform, label, architecture, releaseUrl, and available.

- [ ] Step 2: Build Features with page header, feature grid, four detailed panels, and CLI matrix. Reuse homepage mockups.

- [ ] Step 3: Build Download cards for macOS, Windows, Linux, and Android using README architecture notes. Unavailable targets show status without a dead link; available targets point to GitHub Releases.

- [ ] Step 4: Implement event delegation for data-copy-command, data-platform-filter, and data-showcase-tab. Update aria-selected, hidden, and success text; guard navigator.clipboard with a fallback message.

- [ ] Step 5: Run pnpm check, pnpm build, pnpm smoke and keyboard-test mobile menu, tabs, FAQ, filter, and copy button; commit:

~~~
git add website/src/data website/src/components/features website/src/components/download website/src/scripts website/src/pages/features.astro website/src/pages/zh/features.astro website/src/pages/download.astro website/src/pages/zh/download.astro
git commit -m "feat(website): add features and downloads"
~~~

## Task 5: Add localized Docs, Blog, and Changelog

**Files:**

- Replace: website/src/content.config.js with website/src/content.config.ts
- Create: website/src/content/docs/en/getting-started.mdx, website/src/content/docs/en/workspaces-and-teams.mdx, website/src/content/docs/en/remote-development.mdx, website/src/content/docs/zh/getting-started.mdx, website/src/content/docs/zh/workspaces-and-teams.mdx, website/src/content/docs/zh/remote-development.mdx
- Create: website/src/content/blog/en/why-teampilot.mdx, website/src/content/blog/zh/why-teampilot.mdx
- Create: website/src/content/changelog/en/3-22-0.mdx, website/src/content/changelog/zh/3-22-0.mdx
- Create: website/src/components/content/ContentIndex.astro, website/src/components/content/ContentArticle.astro
- Create: website/src/pages/docs/index.astro, website/src/pages/docs/[...slug].astro
- Create: website/src/pages/zh/docs/index.astro, website/src/pages/zh/docs/[...slug].astro
- Replace: website/src/pages/blog/index.astro, website/src/pages/blog/[...slug].astro, website/src/pages/changelog.astro
- Create: website/src/pages/zh/blog/index.astro, website/src/pages/zh/blog/[...slug].astro, website/src/pages/zh/changelog.astro

**Interfaces:**

- Consumes: SiteLayout, Astro Content Layer, and locale helpers.
- Produces: typed docs/blog/changelog collections, localized indexes, static articles, and two RSS feeds.

- [ ] Step 1: Define glob-loaded schemas with locale, title, description, publishDate, slug, optional tags/readTime/version/featured, and z.coerce.date().

- [ ] Step 2: Write matching English and Chinese starter entries for installation, workspaces/teams, remote development, product introduction, and release 3.22.0. Paraphrase README.md and link to real destinations.

- [ ] Step 3: Implement ContentIndex accepting title, description, entries, locale and ContentArticle accepting entry, locale. Use locale-preserving links.

- [ ] Step 4: Generate static paths with getCollection and getStaticPaths, filtering each route to its own locale. Missing translations must not create wrong-language pages. Generate English and Chinese blog RSS.

- [ ] Step 5: Run pnpm check, pnpm build, pnpm smoke, inspect all outputs under dist/docs, dist/zh/docs, dist/blog, dist/zh/blog, dist/changelog, and dist/zh/changelog; commit:

~~~
git add website/src/content.config.ts website/src/content website/src/pages/docs website/src/pages/zh/docs website/src/pages/blog website/src/pages/zh/blog website/src/pages/changelog.astro website/src/pages/zh/changelog.astro website/src/components/content
git commit -m "feat(website): add localized content collections"
~~~

## Task 6: Finish SEO, assets, 404, and GitHub Pages

**Files:**

- Modify: website/src/layouts/Meta.astro, website/src/layouts/SiteLayout.astro, website/astro.config.mjs, website/src/pages/404.astro, website/scripts/check-build.mjs
- Create: website/public/og-image.svg, website/public/robots.txt, .github/workflows/website-pages.yml

**Interfaces:**

- Consumes: site config, locale helpers, all routes, and built output.
- Produces: locale-aware metadata, sitemap/robots, branded 404, and automatic Pages deployment.

- [ ] Step 1: Make Meta accept title, description, locale, canonical, and image. Emit html lang, canonical, og:locale en_US/zh_CN, alternate links, and Open Graph/Twitter image tags.

- [ ] Step 2: Create SVG social preview with TeamPilot text/icon and CSS-safe colors. Copy assets/icon.svg to website/public/brand-icon.svg. Do not add client/google_fonts/ or generated client assets.

- [ ] Step 3: Add workflow using pnpm/action-setup@v4 version 9.14.2, setup-node@v4 Node 22, pnpm install --frozen-lockfile, PUBLIC_SITE_URL and PUBLIC_BASE_PATH, pnpm build, pnpm smoke, actions/upload-pages-artifact@v3, and actions/deploy-pages@v4. Trigger on website/**, the workflow, and assets/icon.svg.

- [ ] Step 4: Extend smoke checks for English and Chinese home/features/download/docs/blog/changelog, 404.html, sitemap-index.xml, canonical/alternate links, and /teampilot/ asset prefixes with PUBLIC_BASE_PATH=/teampilot.

- [ ] Step 5: Verify:

~~~
cd website
PUBLIC_SITE_URL=https://hhoao.github.io/teampilot/ PUBLIC_BASE_PATH=/teampilot pnpm build
PUBLIC_SITE_URL=https://hhoao.github.io/teampilot/ PUBLIC_BASE_PATH=/teampilot pnpm smoke
~~~

Commit only website and Pages files:

~~~
git add .github/workflows/website-pages.yml website
git commit -m "ci(website): deploy Astro site to GitHub Pages"
~~~

## Task 7: Full verification and handoff

**Files:**

- Test: website/scripts/check-build.mjs
- Inspect: all website files and .github/workflows/website-pages.yml

- [ ] Step 1: Run pnpm install --frozen-lockfile, pnpm check, pnpm build, and pnpm smoke from website/.

- [ ] Step 2: Run production preview with PUBLIC_SITE_URL=https://hhoao.github.io/teampilot/ and PUBLIC_BASE_PATH=/teampilot. Check 1440px and 375px for navigation, locale switches, mockup overflow, tabs, FAQ, filter, copy feedback, real links, 404, and reduced motion.

- [ ] Step 3: Run git status --short and git diff --check -- website .github/workflows/website-pages.yml. Existing dirty client submodules must remain untouched.

- [ ] Step 4: Confirm Settings -> Pages uses GitHub Actions. Report the live URL only after the workflow run and live URL have been checked.
