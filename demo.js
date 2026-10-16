// Modo demonstração: se o config.js ainda não tem os dados do Supabase,
// o app funciona com um banco de exemplo guardado só neste navegador.
(function () {
  const cfg = window.APP_CONFIG || {};
  if (cfg.SUPABASE_URL && !/SEU-PROJETO/.test(cfg.SUPABASE_URL)) return;
  window.APP_CONFIG = { SUPABASE_URL: "demo", SUPABASE_ANON_KEY: "demo", DEMO: true };

  const CHAVE = "barbearia-demo-v1";
  const PRECOS = { corte: ["Corte", 45], barba: ["Barba na navalha", 35], combo: ["Corte + barba", 70],
    degrade: ["Degradê", 55], pezinho: ["Pezinho e acabamento", 15], sobrancelha: ["Sobrancelha", 20] };
  const pad = n => String(n).padStart(2, "0");
  const ymd = d => d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate());
  const dia = n => { const d = new Date(); d.setDate(d.getDate() + n); return ymd(d); };
  const dig = t => String(t || "").replace(/\D/g, "");
  const min = h => { const [a, b] = h.split(":").map(Number); return a * 60 + b; };
  const uid = () => (crypto.randomUUID ? crypto.randomUUID() : "id" + Math.random().toString(36).slice(2));

  function exemplo(servico, barbeiro, d, hora, nome, telefone, status, pagamento) {
    return { id: uid(), servico, servico_nome: PRECOS[servico][0], duracao: 30, preco: PRECOS[servico][1], cashback_usado: 0,
      barbeiro, data: d, hora, nome, telefone, status, pagamento, criado_em: new Date().toISOString() };
  }
  function semear() {
    return {
      ags: [
        exemplo("corte", "rafael", dia(-7), "10:00", "Carlos (exemplo)", "(11) 90000-0001", "concluido", "pago"),
        exemplo("combo", "diego", dia(-3), "15:00", "Bruno (exemplo)", "(11) 90000-0002", "concluido", "pago"),
        exemplo("corte", "rafael", dia(0), "14:00", "Carlos (exemplo)", "(11) 90000-0001", "confirmado", "pago"),
        exemplo("barba", "diego", dia(0), "16:30", "André (exemplo)", "(11) 90000-0003", "confirmado", "informado"),
        exemplo("degrade", "marcos", dia(1), "10:30", "Lucas (exemplo)", "(11) 90000-0004", "confirmado", "pendente"),
        exemplo("corte", "rafael", dia(1), "11:00", "Bruno (exemplo)", "(11) 90000-0002", "confirmado", "pendente"),
        exemplo("sobrancelha", "marcos", dia(2), "09:00", "Pedro (exemplo)", "(11) 90000-0005", "confirmado", "pendente")
      ],
      config: { pix: { chave: "barbearia.exemplo@email.com", nome: "Navalha e Tesoura", cidade: "Sao Paulo" }, whatsapp: {} },
      logado: false
    };
  }
  let db;
  try { db = JSON.parse(localStorage.getItem(CHAVE)) || semear(); } catch (e) { db = semear(); }
  const salvar = () => { try { localStorage.setItem(CHAVE, JSON.stringify(db)); } catch (e) {} };
  salvar();
  window.__demoReset = () => { db = semear(); salvar(); location.reload(); };

  function saldo(tel) {
    const k = dig(tel); if (k.length < 10) return 0; let s = 0;
    db.ags.forEach(a => { if (dig(a.telefone) !== k) return;
      if (a.status === "concluido") s += (a.preco - a.cashback_usado) * 0.05;
      if (a.status !== "cancelado") s -= a.cashback_usado; });
    return Math.max(0, Math.round(s * 100) / 100);
  }
  const erro = m => ({ data: null, error: { message: m } });
  const ok = d => ({ data: d, error: null });
  const rpc = {
    horarios_ocupados: p => ok(db.ags.filter(a => a.data === p.p_data && a.status !== "cancelado")
      .map(a => ({ barbeiro: a.barbeiro, hora: a.hora, duracao: a.duracao }))),
    saldo_cashback: p => ok(saldo(p.p_tel)),
    meus_agendamentos: p => ok(db.ags.filter(a => p.p_ids.includes(a.id))),
    eh_admin: () => ok(!!db.logado),
    criar_agendamento: p => {
      const s = PRECOS[p.p_servico]; if (!s) return erro("servico_invalido");
      const m = min(p.p_hora);
      if (db.ags.some(a => a.barbeiro === p.p_barbeiro && a.data === p.p_data && a.status !== "cancelado"
        && m < min(a.hora) + a.duracao && m + 30 > min(a.hora))) return erro("horario_ocupado");
      const cb = p.p_usar_cashback ? Math.min(saldo(p.p_telefone), s[1]) : 0;
      const r = exemplo(p.p_servico, p.p_barbeiro, p.p_data, p.p_hora, p.p_nome.trim(), p.p_telefone.trim(), "confirmado", "pendente");
      r.cashback_usado = cb; db.ags.push(r); salvar(); return ok(r);
    },
    cliente_atualiza: p => {
      const a = db.ags.find(x => x.id === p.p_id); if (!a) return ok(null);
      if (p.p_acao === "cancelar" && a.status === "confirmado") a.status = "cancelado";
      if (p.p_acao === "paguei" && a.pagamento === "pendente") a.pagamento = "informado";
      if (p.p_acao === "avisei") a.avisado_barbeiro = new Date().toISOString();
      salvar(); return ok(null);
    }
  };
  function tabela(nome) {
    const lista = () => nome === "config" ? Object.entries(db.config).map(([id, dados]) => ({ id, dados })) : db.ags.slice();
    const q = {
      _upd: null,
      select() { return q; }, order() { return q; },
      limit() { return Promise.resolve(db.logado || nome === "config" ? ok(lista()) : ok([])); },
      then(res, rej) { return Promise.resolve(ok(lista())).then(res, rej); },
      update(v) { q._upd = v; return q; },
      eq(_, id) { const a = db.ags.find(x => x.id === id); if (a && db.logado) Object.assign(a, q._upd); salvar(); return Promise.resolve(ok(null)); },
      upsert(r) { if (!db.logado) return Promise.resolve(erro("sem_permissao")); db.config[r.id] = r.dados; salvar(); return Promise.resolve(ok(null)); }
    };
    return q;
  }
  window.supabase = { createClient: () => ({
    rpc: async (n, p) => (rpc[n] ? rpc[n](p || {}) : erro("rpc_inexistente")),
    from: tabela,
    auth: {
      getSession: async () => ({ data: { session: db.logado ? { demo: true } : null } }),
      signInWithPassword: async () => { db.logado = true; salvar(); return { error: null }; },
      signOut: async () => { db.logado = false; salvar(); return { error: null }; }
    }
  }) };
})();
