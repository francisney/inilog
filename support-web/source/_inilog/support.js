'use strict';
const toast = message => {
  const node = document.getElementById('toast');
  if (!node) return;
  node.textContent = message; node.hidden = false;
  clearTimeout(window.inilogToast); window.inilogToast = setTimeout(() => node.hidden = true, 3200);
};
document.addEventListener('click', async event => {
  const copy = event.target.closest('[data-copy], [data-copy-target]');
  if (copy) {
    const value = copy.hasAttribute('data-copy-target') ? document.getElementById(copy.dataset.copyTarget)?.textContent : copy.dataset.copy;
    if (value == null) return;
    try {
      if (navigator.clipboard && window.isSecureContext) await navigator.clipboard.writeText(value);
      else {
        const field = document.createElement('textarea'); field.value = value; field.setAttribute('aria-label', 'Texto para copiar');
        document.body.append(field); field.select();
        if (!document.execCommand('copy')) throw new Error('copy');
        field.remove(); copy.focus();
      }
      toast('Copiado para a área de transferência.');
    } catch { toast('Não foi possível copiar. Selecione o texto e copie manualmente.'); }
  }
});
document.addEventListener('submit', event => {
  const form = event.target;
  if (form.dataset.confirm && !window.confirm(form.dataset.confirm)) { event.preventDefault(); return; }
  if (form.checkValidity()) {
    // Não desabilitar antes do envio: botões nomeados podem fazer parte da requisição.
    setTimeout(() => form.querySelectorAll('button[type=submit]').forEach(button => button.disabled = true), 0);
  }
});
document.addEventListener('keydown', event => {
  if (event.key === '/' && !/INPUT|TEXTAREA|SELECT/.test(document.activeElement.tagName)) {
    const search = document.querySelector('input[type=search]');
    if (search) { event.preventDefault(); search.focus(); }
  }
});
