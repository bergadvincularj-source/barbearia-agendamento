# Navalha & Tesoura · Agendamento

Site de agendamento da barbearia. O cliente agenda sem login: escolhe o serviço, o barbeiro, o dia e o horário (30 minutos cada), paga por Pix e avisa pelo WhatsApp. A equipe entra em "Acesso da equipe" com e-mail e senha para ver a agenda, marcar pagamentos e atendimentos concluídos, consultar clientes e cashback, e configurar o Pix e os WhatsApps dos barbeiros.

## Como colocar no ar

### 1. Banco de dados (Supabase, gratuito)
1. Crie uma conta em https://supabase.com e um projeto novo (região São Paulo).
2. Abra **SQL Editor**, cole todo o conteúdo de `supabase/schema.sql` e clique em **Run**.
3. Em **Authentication > Users > Add user**, crie o usuário do administrador com e-mail e senha.
4. No SQL Editor, rode trocando pelo e-mail criado:
   ```sql
   insert into public.admins (user_id) select id from auth.users where email = 'seu@email.com';
   ```
5. Em **Project Settings > API**, copie a **Project URL** e a chave **anon public**.

### 2. Configurar o site
Edite `config.js` e cole a URL e a chave anon. A chave anon é pública: quem protege os dados são as regras do banco.

### 3. Publicar (Vercel, gratuito)
1. Crie uma conta em https://vercel.com entrando com o GitHub.
2. **Add New > Project**, escolha este repositório e clique em **Deploy** (não precisa configurar nada).
3. O site fica em um endereço como `https://barbearia.vercel.app`. Esse é o link para os clientes.

### 4. Primeiros ajustes
Entre em **Acesso da equipe**, aba **Configurações**, e cadastre o WhatsApp de cada barbeiro e a chave Pix.

## Personalizar
- Nome da barbearia, serviços, barbeiros e horários ficam no início do script em `index.html` (`SERVICOS`, `BARBEIROS`, `HORARIO`, `NOME_LOJA`).
- Se mudar preços ou barbeiros, mude também em `supabase/schema.sql` (funções `preco_servico` e `criar_agendamento`) e rode de novo no SQL Editor. O preço cobrado vem do banco, para ninguém alterar pelo navegador.
- Cashback: 5% em `CASHBACK` (index.html) e em `saldo_cashback` (schema.sql).

## Limites
- O Pix é confirmado manualmente pela equipe ("Pix recebido"). Confirmação automática exige integração com banco ou intermediário (Mercado Pago, Asaas).
- Os avisos de WhatsApp abrem o app com a mensagem pronta; a pessoa toca em enviar. Envio automático exige a API do WhatsApp Business.
