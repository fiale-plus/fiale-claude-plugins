import { JSDOM } from 'jsdom';
import { Readability } from '@mozilla/readability';
import TurndownService from 'turndown';
import { gfm } from 'turndown-plugin-gfm';

export function htmlToMarkdown(html, url, { useReadability = true } = {}) {
  const dom = new JSDOM(html, { url });
  let content;

  if (useReadability) {
    const reader = new Readability(dom.window.document);
    const article = reader.parse();
    if (article) {
      content = article.content;
    } else {
      // Readability couldn't parse — fall back to body
      content = dom.window.document.body?.innerHTML || html;
    }
  } else {
    content = dom.window.document.body?.innerHTML || html;
  }

  const td = new TurndownService({
    headingStyle: 'atx',
    codeBlockStyle: 'fenced',
    bulletListMarker: '-',
  });
  td.use(gfm);

  // Remove script/style/nav noise
  td.remove(['script', 'style', 'nav', 'footer', 'iframe', 'noscript']);

  return td.turndown(content);
}
