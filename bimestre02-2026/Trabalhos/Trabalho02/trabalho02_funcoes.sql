/* =====================================================================
   TRABALHO PRÁTICO 02 - Functions no PostgreSQL (PL/pgSQL)
   Gestão de Banco de Dados - 2º Bimestre / 2026
   Aluno: Kauã Cesar da Silva        RA: 007556
   Tema: Locadora de Equipamentos de Camping e Aventura ("TrilhaCerta")
   ---------------------------------------------------------------------
   CONTEXTO
   Este trabalho é a continuação do Trabalho 01. Ele usa as mesmas
   tabelas (clientes, categorias, equipamentos, locacoes, itens_locacao
   e pagamentos) e a mesma massa de dados do script_trabalho01.sql.
   Execute primeiro o script do Trabalho 01 e depois este arquivo.

   FUNCTIONS CRIADAS
   1. fn_status_cliente        -> consulta com regra de negócio (TEXT)
   2. fn_valor_total_locacao   -> cálculo escalar com COALESCE (NUMERIC)
   3. fn_saldo_devedor         -> cálculo que reutiliza outra function
   4. fn_multa_atraso          -> regra de negócio com parâmetro padrão
   5. fn_atualiza_atrasadas    -> processamento em lote com LOOP (INTEGER)

   REGRAS DE NEGÓCIO ASSUMIDAS (definidas a partir do Trabalho 01)
   - Valor da locação = soma(quantidade x valor_diaria dos itens) x dias,
     sendo dias = data_prevista - data_retirada (mínimo de 1 dia).
     Essa é a mesma conta da consulta 3.7 do Trabalho 01.
   - Locação CANCELADA não gera cobrança.
   - Multa por atraso = dias de atraso x valor das diárias da locação
     x percentual da multa (padrão de 10% ao dia).
   ===================================================================== */


/* ---------------------------------------------------------------------
   FUNCTION 1: fn_status_cliente
   Tipo de retorno: TEXT
   Objetivo: informar o nome do cliente, se ele está ativo ou inativo e
   quantas locações em andamento (ABERTA ou ATRASADA) ele possui.
   Utilidade: o atendente consulta rapidamente a situação do cliente
   antes de liberar uma nova locação.
   Técnicas: SELECT INTO, comando FOUND, IF/ELSE e concatenação.
   --------------------------------------------------------------------- */
CREATE OR REPLACE FUNCTION fn_status_cliente(p_id_cliente INT)
RETURNS TEXT AS $$
DECLARE
    v_nome      TEXT;
    v_ativo     BOOLEAN;
    v_em_aberto INT;
BEGIN
    -- Busca os dados do cliente
    SELECT nome, ativo
      INTO v_nome, v_ativo
      FROM clientes
     WHERE id_cliente = p_id_cliente;

    -- FOUND é falso quando o SELECT não encontrou nenhuma linha
    IF NOT FOUND THEN
        RETURN 'Cliente não encontrado!';
    END IF;

    -- Conta as locações ainda não devolvidas
    SELECT COUNT(*)
      INTO v_em_aberto
      FROM locacoes
     WHERE id_cliente = p_id_cliente
       AND status IN ('ABERTA', 'ATRASADA');

    IF v_ativo THEN
        RETURN v_nome || ' - Cliente Ativo - ' || v_em_aberto || ' locação(ões) em andamento';
    ELSE
        RETURN v_nome || ' - Cliente Inativo - locação bloqueada';
    END IF;
END;
$$ LANGUAGE plpgsql;


/* ---------------------------------------------------------------------
   FUNCTION 2: fn_valor_total_locacao
   Tipo de retorno: NUMERIC(10,2)
   Objetivo: calcular o valor total de uma locação (itens x diárias).
   Utilidade: evita repetir a conta da consulta 3.7 em várias queries e
   garante que toda a loja use a mesma regra de cálculo.
   Técnicas: SELECT INTO, COALESCE (trata locação sem itens), GREATEST
   (garante no mínimo 1 diária) e IF para locação cancelada.
   --------------------------------------------------------------------- */
CREATE OR REPLACE FUNCTION fn_valor_total_locacao(p_id_locacao INT)
RETURNS NUMERIC(10,2) AS $$
DECLARE
    v_dias          INT;
    v_status        VARCHAR(15);
    v_soma_diarias  NUMERIC(10,2);
BEGIN
    -- Quantidade de dias da locação (mínimo 1) e status
    SELECT GREATEST(data_prevista - data_retirada, 1), status
      INTO v_dias, v_status
      FROM locacoes
     WHERE id_locacao = p_id_locacao;

    -- Locação inexistente ou cancelada não gera cobrança
    IF NOT FOUND OR v_status = 'CANCELADA' THEN
        RETURN 0.00;
    END IF;

    -- Soma das diárias de todos os itens (COALESCE evita retorno NULL)
    SELECT COALESCE(SUM(quantidade * valor_diaria), 0.00)
      INTO v_soma_diarias
      FROM itens_locacao
     WHERE id_locacao = p_id_locacao;

    RETURN v_soma_diarias * v_dias;
END;
$$ LANGUAGE plpgsql;


/* ---------------------------------------------------------------------
   FUNCTION 3: fn_saldo_devedor
   Tipo de retorno: NUMERIC(10,2)
   Objetivo: calcular quanto ainda falta o cliente pagar em uma locação
   (valor total - soma dos pagamentos já recebidos).
   Utilidade: controle financeiro e cobrança de clientes em débito.
   Técnicas: chamada de outra function (fn_valor_total_locacao) e
   COALESCE para locações sem nenhum pagamento registrado.
   Obs.: resultado 0 = quitada; resultado negativo = cliente pagou a mais.
   --------------------------------------------------------------------- */
CREATE OR REPLACE FUNCTION fn_saldo_devedor(p_id_locacao INT)
RETURNS NUMERIC(10,2) AS $$
DECLARE
    v_total NUMERIC(10,2);
    v_pago  NUMERIC(10,2);
BEGIN
    v_total := fn_valor_total_locacao(p_id_locacao);

    SELECT COALESCE(SUM(valor), 0.00)
      INTO v_pago
      FROM pagamentos
     WHERE id_locacao = p_id_locacao;

    RETURN v_total - v_pago;
END;
$$ LANGUAGE plpgsql;


/* ---------------------------------------------------------------------
   FUNCTION 4: fn_multa_atraso
   Tipo de retorno: NUMERIC(10,2)
   Objetivo: calcular a multa de uma locação devolvida (ou ainda não
   devolvida) depois da data prevista.
   Regra: multa = dias de atraso x soma das diárias x percentual / 100.
   Utilidade: cobrança automática e padronizada de atrasos.
   Técnicas: parâmetro com valor padrão (DEFAULT), CASE, GREATEST e
   COALESCE. Se a locação não foi devolvida, o atraso é contado até hoje.
   --------------------------------------------------------------------- */
CREATE OR REPLACE FUNCTION fn_multa_atraso(
    p_id_locacao INT,
    p_percentual NUMERIC DEFAULT 10
)
RETURNS NUMERIC(10,2) AS $$
DECLARE
    v_data_prevista  DATE;
    v_data_devolucao DATE;
    v_status         VARCHAR(15);
    v_dias_atraso    INT;
    v_soma_diarias   NUMERIC(10,2);
BEGIN
    SELECT data_prevista, data_devolucao, status
      INTO v_data_prevista, v_data_devolucao, v_status
      FROM locacoes
     WHERE id_locacao = p_id_locacao;

    IF NOT FOUND OR v_status = 'CANCELADA' THEN
        RETURN 0.00;
    END IF;

    -- Se já devolveu, conta até a devolução; se não, conta até hoje.
    -- GREATEST(...,0) impede atraso negativo (devolução antecipada).
    v_dias_atraso := GREATEST(
        COALESCE(v_data_devolucao, CURRENT_DATE) - v_data_prevista, 0
    );

    IF v_dias_atraso = 0 THEN
        RETURN 0.00;
    END IF;

    SELECT COALESCE(SUM(quantidade * valor_diaria), 0.00)
      INTO v_soma_diarias
      FROM itens_locacao
     WHERE id_locacao = p_id_locacao;

    RETURN ROUND(v_dias_atraso * v_soma_diarias * (p_percentual / 100), 2);
END;
$$ LANGUAGE plpgsql;


/* ---------------------------------------------------------------------
   FUNCTION 5: fn_atualiza_atrasadas
   Tipo de retorno: INTEGER (quantidade de locações atualizadas)
   Objetivo: rotina de atualização em lote. Percorre as locações
   ABERTAS que passaram da data prevista sem devolução e muda o status
   delas para ATRASADA.
   Utilidade: rodar diariamente para manter os status corretos sem
   precisar atualizar locação por locação manualmente.
   Técnicas: FOR ... LOOP com RECORD, UPDATE dentro do laço, contador
   e parâmetro com valor padrão (data de referência = hoje).
   --------------------------------------------------------------------- */
CREATE OR REPLACE FUNCTION fn_atualiza_atrasadas(p_data_ref DATE DEFAULT CURRENT_DATE)
RETURNS INTEGER AS $$
DECLARE
    reg     RECORD;
    v_total INTEGER := 0;
BEGIN
    FOR reg IN (
        SELECT id_locacao
          FROM locacoes
         WHERE status = 'ABERTA'
           AND data_devolucao IS NULL
           AND data_prevista < p_data_ref
    ) LOOP
        UPDATE locacoes
           SET status = 'ATRASADA'
         WHERE id_locacao = reg.id_locacao;

        v_total := v_total + 1;
    END LOOP;

    RETURN v_total;
END;
$$ LANGUAGE plpgsql;


/* =====================================================================
   EXECUÇÃO E VALIDAÇÃO DAS FUNCTIONS (base TrilhaCerta)
   ===================================================================== */

-- ---- Function 1: status do cliente ----
SELECT fn_status_cliente(1);    -- cliente ativo
SELECT fn_status_cliente(8);    -- cliente inativo (Henrique)
SELECT fn_status_cliente(99);   -- id inexistente

-- Usando em uma consulta com todos os clientes
SELECT c.id_cliente, fn_status_cliente(c.id_cliente) AS situacao
FROM   clientes c
ORDER  BY c.id_cliente;

-- ---- Function 2: valor total da locação ----
SELECT fn_valor_total_locacao(1);    -- esperado: 285.00
SELECT fn_valor_total_locacao(5);    -- cancelada: 0.00
SELECT fn_valor_total_locacao(99);   -- inexistente: 0.00

-- ---- Function 3: saldo devedor ----
SELECT fn_saldo_devedor(4);    -- quitada: 0.00
SELECT fn_saldo_devedor(9);    -- esperado: 275.00 (475,00 - 200,00)

-- Relatório de todas as locações: total, pago e saldo
SELECT l.id_locacao,
       c.nome                            AS cliente,
       l.status,
       fn_valor_total_locacao(l.id_locacao) AS valor_total,
       fn_saldo_devedor(l.id_locacao)       AS saldo_devedor
FROM   locacoes l
JOIN   clientes c ON c.id_cliente = l.id_cliente
ORDER  BY l.id_locacao;

-- ---- Function 4: multa por atraso ----
SELECT fn_multa_atraso(2);        -- devolvida 2 dias depois: 2 x 113,00 x 10% = 22.60
SELECT fn_multa_atraso(1);        -- devolvida no prazo: 0.00
SELECT fn_multa_atraso(9, 15);    -- ainda não devolvida, multa de 15%

-- Locações com multa a cobrar
SELECT l.id_locacao, c.nome AS cliente, l.status,
       fn_multa_atraso(l.id_locacao) AS multa
FROM   locacoes l
JOIN   clientes c ON c.id_cliente = l.id_cliente
WHERE  fn_multa_atraso(l.id_locacao) > 0
ORDER  BY multa DESC;

-- ---- Function 5: atualização em lote (altera dados!) ----
-- Antes: veja os status atuais
SELECT id_locacao, data_prevista, status FROM locacoes ORDER BY id_locacao;

-- Executa a rotina (retorna quantas locações foram marcadas como ATRASADA)
SELECT fn_atualiza_atrasadas();

-- Depois: confira que a locação 10 (prevista p/ 05/11) virou ATRASADA
SELECT id_locacao, data_prevista, status FROM locacoes ORDER BY id_locacao;

-- FIM DO SCRIPT
