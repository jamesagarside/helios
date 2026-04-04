/**
 * Helios GCS — Docs Browser
 *
 * Loads markdown files from ../docs/, renders them as HTML,
 * and provides sidebar navigation with deep linking via ?page=slug.
 *
 * Security: Only loads .md files from the local docs/ directory (same origin).
 * Content is sanitised through the markdown renderer which escapes HTML entities
 * in code blocks and does not pass through raw HTML from markdown source.
 */

// Docs markdown files live in docs/ alongside index.html.
var DOCS_BASE = 'docs/';

// Allowed page slugs — only these can be loaded (prevents arbitrary file reads)
const ALLOWED_SLUGS = new Set([
  'getting-started', 'installation', 'connection-guide',
  'features-overview', 'fly_view', 'mission_planning',
  'analyse-view', 'video-streaming', 'setup-guide',
  'points_of_interest', 'corridor-scan', 'no_fly_zones', 'terrain-planning',
  'emergency-procedures', 'gimbal-control', 'guided-commands', 'joystick-control',
  'mavlink-terminal', 'diagnostic_panels', 'simulate',
  'building-from-source', 'architecture', 'telemetry-schema', 'ci-cd', 'contributing', 'website',
]);

// Sidebar structure — order matters
const DOCS_NAV = [
  {
    heading: 'Getting Started',
    pages: [
      { slug: 'getting-started', title: 'Quick Start' },
      { slug: 'installation', title: 'Installation' },
      { slug: 'connection-guide', title: 'Connecting' },
    ],
  },
  {
    heading: 'Features',
    pages: [
      { slug: 'features-overview', title: 'Overview' },
      { slug: 'fly_view', title: 'Fly View' },
      { slug: 'mission_planning', title: 'Mission Planning' },
      { slug: 'analyse-view', title: 'Data & Analytics' },
      { slug: 'video-streaming', title: 'Video Streaming' },
      { slug: 'setup-guide', title: 'Setup & Config' },
    ],
  },
  {
    heading: 'Mission Patterns',
    pages: [
      { slug: 'points_of_interest', title: 'Points of Interest' },
      { slug: 'corridor-scan', title: 'Corridor Scan' },
      { slug: 'no_fly_zones', title: 'Airspace & NFZ' },
      { slug: 'terrain-planning', title: 'Terrain Planning' },
    ],
  },
  {
    heading: 'Flight Operations',
    pages: [
      { slug: 'emergency-procedures', title: 'Emergency Procedures' },
      { slug: 'gimbal-control', title: 'Gimbal Control' },
      { slug: 'guided-commands', title: 'Guided Commands' },
      { slug: 'joystick-control', title: 'Joystick / Gamepad' },
    ],
  },
  {
    heading: 'Advanced',
    pages: [
      { slug: 'mavlink-terminal', title: 'MAVLink Terminal' },
      { slug: 'diagnostic_panels', title: 'Diagnostic Panels' },
      { slug: 'simulate', title: 'SITL Simulator' },
    ],
  },
  {
    heading: 'Development',
    pages: [
      { slug: 'building-from-source', title: 'Building from Source' },
      { slug: 'architecture', title: 'Architecture' },
      { slug: 'telemetry-schema', title: 'Telemetry Schema' },
      { slug: 'ci-cd', title: 'CI/CD' },
      { slug: 'contributing', title: 'Contributing' },
      { slug: 'website', title: 'Website' },
    ],
  },
];

// ── Minimal Markdown to HTML converter ───────────────────────────────────────
// Only processes markdown syntax — raw HTML tags in the source are escaped.

function escapeHtml(text) {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function inlineFormat(text) {
  let s = escapeHtml(text);
  // Code spans first
  s = s.replace(/`([^`]+)`/g, '<code>$1</code>');
  // Bold
  s = s.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
  // Italic
  s = s.replace(/\*([^*]+)\*/g, '<em>$1</em>');
  // Links — only allow http(s) and relative links
  s = s.replace(/\[([^\]]+)\]\(([^)]+)\)/g, function(_, label, href) {
    if (href.startsWith('http://') || href.startsWith('https://') || !href.includes(':')) {
      return '<a href="' + href + '">' + label + '</a>';
    }
    return label;
  });
  return s;
}

function parseCells(line) {
  return line.split('|').slice(1, -1).map(function(c) { return c.trim(); });
}

function renderMarkdown(md) {
  var lines = md.split('\n');
  var parts = [];
  var inList = false;
  var inOl = false;
  var inTable = false;
  var inCodeBlock = false;
  var codeBuffer = '';
  var inBlockquote = false;

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];

    // Code blocks
    if (line.trimStart().startsWith('```')) {
      if (inCodeBlock) {
        parts.push('<pre><code>' + escapeHtml(codeBuffer) + '</code></pre>');
        codeBuffer = '';
        inCodeBlock = false;
      } else {
        inCodeBlock = true;
      }
      continue;
    }
    if (inCodeBlock) {
      codeBuffer += line + '\n';
      continue;
    }

    // Close lists if needed
    if (inList && !line.match(/^[\s]*[-*] /)) {
      parts.push('</ul>');
      inList = false;
    }
    if (inOl && !line.match(/^[\s]*\d+\. /)) {
      parts.push('</ol>');
      inOl = false;
    }

    // Blockquote
    if (line.startsWith('> ')) {
      if (!inBlockquote) {
        parts.push('<blockquote>');
        inBlockquote = true;
      }
      parts.push('<p>' + inlineFormat(line.slice(2)) + '</p>');
      continue;
    } else if (inBlockquote) {
      parts.push('</blockquote>');
      inBlockquote = false;
    }

    // HR
    if (line.match(/^---+$/)) {
      parts.push('<hr>');
      continue;
    }

    // Headings
    var hMatch = line.match(/^(#{1,6})\s+(.*)/);
    if (hMatch) {
      var level = hMatch[1].length;
      var text = hMatch[2];
      var id = text.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
      parts.push('<h' + level + ' id="' + escapeHtml(id) + '">' + inlineFormat(text) + '</h' + level + '>');
      continue;
    }

    // Table
    if (line.includes('|') && line.trim().startsWith('|')) {
      if (!inTable) {
        inTable = true;
        parts.push('<table>');
        var cells = parseCells(line);
        parts.push('<thead><tr>' + cells.map(function(c) { return '<th>' + inlineFormat(c) + '</th>'; }).join('') + '</tr></thead><tbody>');
        i++; // skip separator line
        continue;
      }
      var cells = parseCells(line);
      parts.push('<tr>' + cells.map(function(c) { return '<td>' + inlineFormat(c) + '</td>'; }).join('') + '</tr>');
      continue;
    } else if (inTable) {
      parts.push('</tbody></table>');
      inTable = false;
    }

    // Unordered list
    var ulMatch = line.match(/^[\s]*[-*]\s+(.*)/);
    if (ulMatch) {
      if (!inList) { parts.push('<ul>'); inList = true; }
      parts.push('<li>' + inlineFormat(ulMatch[1]) + '</li>');
      continue;
    }

    // Ordered list
    var olMatch = line.match(/^[\s]*\d+\.\s+(.*)/);
    if (olMatch) {
      if (!inOl) { parts.push('<ol>'); inOl = true; }
      parts.push('<li>' + inlineFormat(olMatch[1]) + '</li>');
      continue;
    }

    // Empty line
    if (line.trim() === '') {
      continue;
    }

    // Paragraph
    parts.push('<p>' + inlineFormat(line) + '</p>');
  }

  // Close any open tags
  if (inList) parts.push('</ul>');
  if (inOl) parts.push('</ol>');
  if (inTable) parts.push('</tbody></table>');
  if (inBlockquote) parts.push('</blockquote>');
  if (inCodeBlock) parts.push('<pre><code>' + escapeHtml(codeBuffer) + '</code></pre>');

  return parts.join('\n');
}

// ── Page Loading ─────────────────────────────────────────────────────────────

async function loadPage(slug) {
  // Validate slug against allowlist
  if (!ALLOWED_SLUGS.has(slug)) {
    slug = 'getting-started';
  }

  var content = document.getElementById('docs-content');
  content.textContent = 'Loading...';

  try {
    var res = await fetch(DOCS_BASE + slug + '.md');
    if (!res.ok) throw new Error('Not found');
    var md = await res.text();
    // renderMarkdown escapes all HTML entities from the source,
    // then constructs safe HTML from known markdown patterns only.
    var rendered = renderMarkdown(md);
    // Using a document fragment via DOMParser for safe insertion
    var parser = new DOMParser();
    var doc = parser.parseFromString('<div>' + rendered + '</div>', 'text/html');
    content.replaceChildren();
    var nodes = doc.body.firstChild.childNodes;
    while (nodes.length > 0) {
      content.appendChild(nodes[0]);
    }
  } catch (e) {
    content.textContent = '';
    var h1 = document.createElement('h1');
    h1.textContent = 'Page not found';
    var p = document.createElement('p');
    p.textContent = 'Could not load ' + slug + '.md.';
    var a = document.createElement('a');
    a.href = 'docs.html?page=getting-started';
    a.textContent = 'Return to Getting Started';
    p.appendChild(document.createTextNode(' '));
    p.appendChild(a);
    content.appendChild(h1);
    content.appendChild(p);
  }

  // Update sidebar active state
  document.querySelectorAll('.docs-sidebar a').forEach(function(a) {
    a.classList.toggle('active', a.dataset.slug === slug);
  });

  // Build right-hand TOC from headings
  buildToc();

  // Update URL
  var url = new URL(window.location);
  url.searchParams.set('page', slug);
  window.history.pushState({}, '', url);

  // Scroll to top
  window.scrollTo(0, 0);

  // Close mobile sidebar
  var sidebar = document.querySelector('.docs-sidebar');
  if (sidebar) sidebar.classList.remove('open');
}

// ── Sidebar Builder ──────────────────────────────────────────────────────────

function buildSidebar() {
  var sidebar = document.getElementById('docs-sidebar');
  sidebar.textContent = '';

  DOCS_NAV.forEach(function(section) {
    var h4 = document.createElement('h4');
    h4.textContent = section.heading;
    sidebar.appendChild(h4);

    section.pages.forEach(function(page) {
      var a = document.createElement('a');
      a.href = 'docs.html?page=' + page.slug;
      a.textContent = page.title;
      a.dataset.slug = page.slug;
      a.addEventListener('click', function(e) {
        e.preventDefault();
        loadPage(page.slug);
      });
      sidebar.appendChild(a);
    });
  });
}

// ── Right-hand TOC ───────────────────────────────────────────────────────────

function buildToc() {
  var toc = document.getElementById('docs-toc');
  if (!toc) return;
  toc.textContent = '';

  var content = document.getElementById('docs-content');
  var headings = content.querySelectorAll('h2, h3');
  if (headings.length === 0) return;

  var title = document.createElement('h4');
  title.textContent = 'On this page';
  toc.appendChild(title);

  headings.forEach(function(h) {
    var a = document.createElement('a');
    a.textContent = h.textContent;
    a.href = '#' + h.id;
    if (h.tagName === 'H3') a.classList.add('toc-h3');
    a.addEventListener('click', function(e) {
      e.preventDefault();
      h.scrollIntoView({ behavior: 'smooth', block: 'start' });
      // Update hash without triggering popstate
      window.history.replaceState({}, '', a.href);
    });
    toc.appendChild(a);
  });

  // Set up scroll spy
  setupScrollSpy(headings);
}

var _scrollSpyCleanup = null;

function setupScrollSpy(headings) {
  // Clean up previous observer
  if (_scrollSpyCleanup) {
    _scrollSpyCleanup();
    _scrollSpyCleanup = null;
  }

  var toc = document.getElementById('docs-toc');
  if (!toc || headings.length === 0) return;

  var tocLinks = toc.querySelectorAll('a');

  var observer = new IntersectionObserver(function(entries) {
    entries.forEach(function(entry) {
      if (entry.isIntersecting) {
        var id = entry.target.id;
        tocLinks.forEach(function(link) {
          link.classList.toggle('active', link.getAttribute('href') === '#' + id);
        });
      }
    });
  }, {
    rootMargin: '-80px 0px -70% 0px',
    threshold: 0
  });

  headings.forEach(function(h) { observer.observe(h); });

  _scrollSpyCleanup = function() {
    observer.disconnect();
  };
}

// ── Init ─────────────────────────────────────────────────────────────────────

document.addEventListener('DOMContentLoaded', function() {
  buildSidebar();

  var params = new URLSearchParams(window.location.search);
  var page = params.get('page') || 'getting-started';
  loadPage(page);
});

// Handle browser back/forward
window.addEventListener('popstate', function() {
  var params = new URLSearchParams(window.location.search);
  var page = params.get('page') || 'getting-started';
  loadPage(page);
});
