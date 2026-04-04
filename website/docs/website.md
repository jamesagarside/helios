# Website

The Helios GCS website at [heliosgcs.com](https://heliosgcs.com) is the public-facing site for the project. It covers product information, feature descriptions, downloads, and this documentation.

## Architecture

The website is a static site built with plain HTML, CSS, and vanilla JavaScript - no build step, no framework, no dependencies.

```
website/
  index.html          # Homepage (product landing page)
  features.html       # Feature details and comparison
  docs.html           # Documentation browser (this page)
  robots.txt          # Search engine crawling directives
  sitemap.xml         # URL list for search engine indexing
  llms.txt            # LLM-readable site summary
  llms-full.txt       # Extended LLM reference
  css/
    style.css          # Global styles and docs layout
    features.css       # Features page specific styles
  js/
    docs.js            # Documentation browser (markdown loader, sidebar, TOC)
  img/
    logo.svg           # Helios logo (header, hero)
    app-icon.svg       # App icon (1024x1024 SVG)
    favicon-48.png     # Favicon for browsers
    favicon-192.png    # Favicon for Google search results
    apple-touch-icon.png  # iOS bookmark icon
    og-image.png       # Social media preview image (1280x640)
  docs/
    getting-started.md # All documentation pages as markdown
    ...
```

### Documentation Browser

The docs page (`docs.html`) uses a client-side markdown renderer in `js/docs.js`. It fetches `.md` files from the `docs/` directory and renders them as HTML with a sidebar, table of contents, and deep linking via `?page=slug` URL parameters.

**Security**: Only files listed in the `ALLOWED_SLUGS` set can be loaded. HTML entities in markdown source are escaped to prevent XSS.

**SEO**: A `<noscript>` fallback provides static HTML links to all doc pages for search engine crawlers that don't execute JavaScript.

### Adding a New Doc Page

1. Create a new `.md` file in `website/docs/`
2. Add the slug to `ALLOWED_SLUGS` in `js/docs.js`
3. Add a navigation entry to `DOCS_NAV` in `js/docs.js` under the appropriate section
4. Add the URL to `website/sitemap.xml`
5. If the page is important, add it to the `<noscript>` fallback in `docs.html`

## Hosting

The website is hosted on **GitHub Pages**, served from the `website/` directory of the repository. GitHub Pages serves static files directly with no server-side processing.

### Limitations

- **No server-side rewrites**: URLs must use `.html` extensions (e.g., `/features.html` not `/features`). GitHub Pages doesn't support clean URL rewrites without Jekyll.
- **No server-side rendering**: All content must be static HTML or client-side JavaScript.
- **Custom domain**: The site uses `heliosgcs.com` configured via a CNAME record pointing to GitHub Pages.

### Deployment

Changes to the `website/` directory on the `main` branch are automatically deployed to GitHub Pages. There is no separate build step - the HTML/CSS/JS files are served as-is.

To preview locally:

```bash
cd website
python3 -m http.server 8000
# Open http://localhost:8000
```

Or use the included helper:

```bash
cd website
./serve.sh
```

## SEO

The website implements several SEO best practices:

### Search Engine Optimisation
- **Meta tags**: Title, description, canonical URL, robots directive on every page
- **Open Graph / Twitter Cards**: Preview images and descriptions for social sharing
- **Structured data (JSON-LD)**: `SoftwareApplication` schema on homepage, `FAQPage` with common questions, `BreadcrumbList` on subpages
- **Sitemap**: `sitemap.xml` listing all indexable URLs with priorities and last-modified dates
- **robots.txt**: Allows all crawlers and points to the sitemap
- **Favicons**: Multiple sizes (48px, 192px) plus Apple Touch icon for Google search results and bookmarks

### LLM Discoverability
- **llms.txt**: Compact summary following the [llmstxt.org](https://llmstxt.org) standard - key facts, features, comparisons, and links
- **llms-full.txt**: Extended reference with architecture details, full feature descriptions, and FAQ
- **Link headers**: `<link rel="help" href="/llms.txt">` in all page heads for crawler discovery

### Search Console
The site is registered with Google Search Console and Bing Webmaster Tools. The sitemap is submitted to both.

## Design

### Theme
The site uses a dark theme matching the Helios app:

| Token | Value | Usage |
| --- | --- | --- |
| `--bg` | `#0D1117` | Page background |
| `--surface` | `#161B22` | Cards, panels |
| `--accent` | `#58A6FF` | Links, highlights, brand colour |
| `--text-primary` | `#E6EDF3` | Headings, body text |
| `--text-secondary` | `#8B949E` | Descriptions, secondary text |
| `--text-tertiary` | `#6E7681` | Muted text, labels |

### Typography
System font stack (`-apple-system, BlinkMacSystemFont, 'Segoe UI', ...`) for body text, monospace stack for code. No web fonts are loaded.

### Responsive
The site is responsive with breakpoints at 768px (mobile) and 1024px (tablet). The docs sidebar becomes a slide-out panel on mobile, and the right-hand TOC is hidden below 1024px.

## Making Changes

### Content changes
- Edit the relevant `.md` file in `website/docs/` for documentation updates
- Edit `index.html` directly for homepage content
- Edit `features.html` directly for feature descriptions

### Style changes
- Global styles: `css/style.css`
- Features page: `css/features.css`
- CSS variables are defined in `:root` at the top of `style.css`

### Adding images
- Place images in `website/img/`
- Use descriptive alt text for accessibility and SEO
- Prefer SVG for icons and logos, optimised PNG for screenshots

### SEO updates
- Update `sitemap.xml` when adding or removing pages
- Update `llms.txt` and `llms-full.txt` when features or product details change
- Keep meta descriptions under 160 characters
