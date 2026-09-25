(() => {
  const key = 'starlight-theme';
  const light = matchMedia('(prefers-color-scheme: light)');
  let preference = 'auto';

  function storedPreference() {
    try {
      const value = localStorage.getItem(key);
      return value === 'light' || value === 'dark' ? value : 'auto';
    } catch {
      return 'auto';
    }
  }

  function storePreference(value) {
    try {
      localStorage.setItem(key, value === 'auto' ? '' : value);
    } catch {
      // Storage can be blocked; keep the selection for this page only.
    }
  }

  function updatePickers() {
    for (const picker of document.querySelectorAll('starlight-theme-select')) {
      const select = picker.querySelector('select');
      if (select) select.value = preference;
      const source = document.querySelector('#theme-icons')?.content.querySelector(`.${preference}`);
      const icon = picker.querySelector('svg.label-icon');
      if (source && icon) icon.replaceChildren(...source.cloneNode(true).childNodes);
    }
  }

  function apply(value, persist = false) {
    preference = value;
    document.documentElement.dataset.theme = value === 'auto' ? (light.matches ? 'light' : 'dark') : value;
    updatePickers();
    if (persist) storePreference(value);
  }

  apply(storedPreference());
  light.addEventListener('change', () => {
    if (preference === 'auto') apply('auto');
  });
  document.addEventListener('DOMContentLoaded', () => {
    updatePickers();
    for (const picker of document.querySelectorAll('starlight-theme-select select')) {
      picker.addEventListener('change', (event) => {
        const value = event.currentTarget.value;
        if (value === 'light' || value === 'dark' || value === 'auto') apply(value, true);
      });
    }
  });
})();
