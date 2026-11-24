// The session and household data live in memory only.
let accessToken = '', refreshToken = '', expiresAt = 0, revision = -1;
let busy = false, totals = {};
let pendingRead = null;
const notice = text => { $('syncStatus').textContent = text; };

async function request(path, body, token) {
  const response = await fetch(casaConfig.url + path, {
    method: 'POST', cache: 'no-store', credentials: 'omit', redirect: 'error',
    headers: {'Content-Type':'application/json', apikey:casaConfig.publishableKey,
      ...(token ? {Authorization:'Bearer ' + token} : {})},
    body: JSON.stringify(body)
  });
  const value = await response.json();
  if (!response.ok) throw Error(value.message || value.error_description || 'Error de conexión');
  return value;
}
function session(value) {
  accessToken = value.access_token;
  refreshToken = value.refresh_token;
  expiresAt = Date.now() + value.expires_in * 1000;
}
async function rpc(name, body = {}) {
  if (Date.now() + 60000 >= expiresAt) {
    session(await request('/auth/v1/token?grant_type=refresh_token', {refresh_token:refreshToken}));
  }
  return request('/rest/v1/rpc/casa_' + name, body, accessToken);
}
function applyRemote(result) {
  const selected = $('memberDay')?.value;
  const {data, slot} = result;
  revision = result.revision;
  currentProfile = profiles[slot].name;
  totals = data.totals || {};
  state = {...initial(), rules:[], stock:[], ...data};
  if (slot >= 2) {
    state.locations = {}; state.meals = {};
    for (const [day, row] of Object.entries(data.answers || {})) mealFor(day)[slot] = row;
    for (const [day, stay] of Object.entries(data.stays || {})) locFor(day)[slot] = stay;
  }
  $('profile').value = currentProfile;
  setView(); renderMeals(); renderPrices();
  if (selected && currentRole()==='member') renderMember(selected);
}
async function synchronize(action, payload) {
  if (!accessToken || busy || (!action && pendingRead)) return;
  if (!action) {
    const initialRevision = revision;
    try {
      pendingRead = rpc('read');
      const result = await pendingRead;
      if (accessToken && !busy && revision === initialRevision && result.revision > revision) applyRemote(result);
    } catch { if (!busy && accessToken) lockCloud('Entra de nuevo para comprobar el acceso a tu hogar.'); }
    finally { pendingRead = null; }
    return;
  }
  busy = true;
  if (action) { document.querySelector('main').inert = true; notice('Guardando…'); }
  try {
    if (pendingRead) await pendingRead;
    const result = await rpc('write',{expected:revision,action,payload});
    applyRemote(result);
    if (action==='add') { $('new').value=''; $('priority').value='normal'; }
    notice('Sincronizado');
  } catch (error) {
    if (action && error.message.includes('revision_conflict')) {
      try { applyRemote(await rpc('read')); notice('Otro móvil ha guardado cambios. Revisa los datos y repite tu cambio.'); }
      catch { lockCloud('Conexión perdida. Vuelve a entrar.'); }
    } else lockCloud(action ? 'No se pudo confirmar el cambio. Entra para comprobarlo.' : 'No se ha podido cargar tu hogar. Comprueba la conexión y el acceso de tu cuenta.');
  } finally { busy=false; document.querySelector('main').inert=false; }
}
function lockCloud(message) {
  accessToken=''; refreshToken=''; revision=-1;
  document.querySelector('main').hidden=true;
  $('authBox').hidden=false; $('exitCloud').hidden=true;
  notice(message);
}
function startCloud() {
  $('account').hidden=false;
  lockCloud('Acceso de prueba · usa solo datos ficticios.');
  if (!/^https:\/\/[a-z0-9-]+\.supabase\.co$/.test(casaConfig.url) || !casaConfig.publishableKey.startsWith('sb_publishable_')) {
    $('authBox').hidden=true; notice('Acceso sincronizado pendiente de configurar.'); return;
  }
  $('profile').disabled=true;
  $('profile').parentElement.querySelector('small').textContent='Perfil asignado a tu cuenta';
  $('profile').previousElementSibling.textContent='Perfil';
  document.querySelector('footer').textContent='Piloto con cuentas de prueba · sincronización entre dispositivos';
  document.querySelector('header .tag').textContent='Piloto conectado · v0.3';
  $('authBox').onsubmit=async e=>{
    e.preventDefault();
    const form=e.currentTarget;
    form.inert=true;
    try {
      session(await request('/auth/v1/token?grant_type=password',{email:$('loginEmail').value.trim(),password:$('loginPass').value}));
      $('loginPass').value='';
      applyRemote(await rpc('read'));
      form.hidden=true; document.querySelector('main').hidden=false; $('exitCloud').hidden=false;
      notice('Sincronizado');
    } catch {lockCloud('No se ha podido entrar. Comprueba tus credenciales y que tengas un hogar asignado.');}
    finally {form.inert=false;}
  };
  $('exitCloud').onclick=async()=>{
    const token=accessToken;
    lockCloud('Sesión cerrada');
    try {await request('/auth/v1/logout?scope=local',{},token);} finally {location.reload();}
  };
  const refresh=()=>{if (!document.hidden && !['INPUT','SELECT','TEXTAREA'].includes(document.activeElement.tagName)) synchronize();};
  setInterval(refresh,5000);
  window.addEventListener('focus',refresh);
  document.addEventListener('visibilitychange',refresh);
}
if (cloudMode) startCloud();
