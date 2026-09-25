document.addEventListener('DOMContentLoaded', () => {
  for (const frame of document.querySelectorAll('.expressive-code figure.frame')) {
    const header = frame.querySelector('figcaption.header');
    const lines = frame.querySelectorAll('pre code .ec-line .code');
    if (!header || !lines.length) continue;

    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'site-copy';
    button.textContent = 'Copy code';
    button.setAttribute('aria-label', 'Copy code to clipboard');

    const status = document.createElement('span');
    status.className = 'site-copy-feedback';
    status.setAttribute('role', 'status');
    status.setAttribute('aria-live', 'polite');
    header.append(button, status);

    button.addEventListener('click', async () => {
      const code = [...lines].map((line) => line.textContent).join('\n');
      try {
        await navigator.clipboard.writeText(code);
        button.textContent = 'Copied';
        status.textContent = 'Copied to clipboard.';
      } catch {
        button.textContent = 'Copy failed';
        status.textContent = 'Copy failed. Select the code manually.';
      }
    });
  }
});
