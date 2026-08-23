// NextKick Web Auth — shared across all dashboard pages
const NK_TOKEN_KEY  = 'nk_token';
const NK_USER_KEY   = 'nk_user';
const API_BASE      = 'https://nextkick.me/api';

const Auth = {
  getToken() { return localStorage.getItem(NK_TOKEN_KEY); },

  getUser() {
    try { return JSON.parse(localStorage.getItem(NK_USER_KEY) || 'null'); }
    catch { return null; }
  },

  save(token, user) {
    localStorage.setItem(NK_TOKEN_KEY, token);
    localStorage.setItem(NK_USER_KEY, JSON.stringify(user));
  },

  clear() {
    localStorage.removeItem(NK_TOKEN_KEY);
    localStorage.removeItem(NK_USER_KEY);
  },

  isLoggedIn() { return !!this.getToken(); },

  // Redirect to login if not authenticated
  guard(loginPage = 'login.html') {
    if (!this.isLoggedIn()) {
      window.location.href = loginPage;
      return false;
    }
    return true;
  },

  async login(email, password) {
    const res = await fetch(`${API_BASE}/auth.php?action=login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
      body: JSON.stringify({ email, password }),
    });
    const data = await res.json();
    if (data.token && data.user) {
      this.save(data.token, data.user);
      return { ok: true, user: data.user };
    }
    return { ok: false, error: data.error || 'Login failed' };
  },

  async logout() {
    const token = this.getToken();
    if (token) {
      try {
        await fetch(`${API_BASE}/auth.php?action=logout`, {
          method: 'POST',
          headers: { 'Authorization': `Bearer ${token}` },
        });
      } catch (_) {}
    }
    this.clear();
    window.location.href = 'login.html';
  },

  headers() {
    const token = this.getToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      ...(token ? { 'Authorization': `Bearer ${token}` } : {}),
    };
  },
};
