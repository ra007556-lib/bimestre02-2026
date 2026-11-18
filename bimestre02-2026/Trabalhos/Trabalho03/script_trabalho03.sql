/* =====================================================================
   TRABALHO PRÁTICO 03 - Operadores e Funções SQL (PostgreSQL)
   Gestão de Banco de Dados - 2º Bimestre / 2026
   Aluno: Kauã Cesar da Silva        RA: 007556
   Tema: Locadora de Equipamentos de Camping e Aventura ("TrilhaCerta")
   ===================================================================== */


/* ---------------------------------------------------------------------
   BLOCO 0 - COMPLEMENTO DE DADOS
   As locações do Trabalho 01 têm datas fixas de 2026. Para que as
   consultas com janela relativa (NOW() - INTERVAL) sempre retornem
   linhas, qualquer que seja o dia da execução, é inserida uma locação
   recente (retirada há 2 dias) com seus itens e um pagamento.
   O NOT EXISTS evita duplicar o registro se o script rodar 2 vezes.
   --------------------------------------------------------------------- */
WITH nova_locacao AS (
    INSERT INTO locacoes (id_cliente, data_retirada, data_prevista, data_devolucao, status)
    SELECT 5, CURRENT_DATE - 2, CURRENT_DATE + 3, NULL, 'ABERTA'
    WHERE NOT EXISTS (
        SELECT 1
          FROM locacoes
         WHERE id_cliente    = 5
           AND data_retirada = CURRENT_DATE - 2
           AND status        = 'ABERTA'
    )
    RETURNING id_locacao
),
novos_itens AS (
    INSERT INTO itens_locacao (id_locacao, id_equipamento, quantidade, valor_diaria)
    SELECT id_locacao, 1, 1, 45.00 FROM nova_locacao      -- Barraca Iglu
    UNION ALL
    SELECT id_locacao, 5, 1, 18.00 FROM nova_locacao      -- Fogareiro
    RETURNING id_item
)
INSERT INTO pagamentos (id_locacao, valor, forma_pagamento, data_pagamento)
SELECT id_locacao, 100.00, 'PIX', CURRENT_DATE - 2
  FROM nova_locacao;


/* =====================================================================
   BLOCO A - OPERADORES LÓGICOS E DE COMPARAÇÃO
   ===================================================================== */

-- Questão 1 - Precedência lógica com parênteses [AND, OR, ( )]
-- Problema de negócio: a loja quer montar uma promoção para equipamentos
-- das categorias Cozinha ou Dormir, mas só aqueles com diária de pelo
-- menos R$ 20,00 (itens muito baratos não entram na promoção).
-- O que mudaria SEM parênteses: o AND é avaliado antes do OR, então a
-- condição viraria  Cozinha  OR  (Dormir AND diária >= 20). Todos os
-- itens de Cozinha entrariam, mesmo os de R$ 18,00 e R$ 15,00 (fogareiro
-- e kit de panelas), e o resultado passaria de 2 para 4 linhas.
SELECT e.nome        AS equipamento,
       cat.nome      AS categoria,
       e.valor_diaria AS diaria
FROM   equipamentos e
JOIN   categorias cat ON cat.id_categoria = e.id_categoria
WHERE  (cat.nome = 'Cozinha' OR cat.nome = 'Dormir')
  AND  e.valor_diaria >= 20
ORDER  BY e.valor_diaria DESC;


-- Questão 2 - Negação e verificação de nulos [NOT IN, IS NULL]
-- Problema de negócio: o atendente precisa listar as locações que ainda
-- estão em andamento, ou seja, que NÃO estão finalizadas nem canceladas
-- e cuja data de devolução (coluna opcional) ainda está nula, para
-- cobrar a devolução dos equipamentos.
SELECT l.id_locacao,
       l.status,
       l.data_prevista,
       l.data_devolucao AS devolucao_real
FROM   locacoes l
WHERE  l.status NOT IN ('FINALIZADA', 'CANCELADA')
  AND  l.data_devolucao IS NULL
ORDER  BY l.data_prevista;


-- Questão 3 - Intervalos inclusivos e listas [BETWEEN, IN]
-- Problema de negócio: o financeiro quer revisar pagamentos de valor
-- médio (de R$ 100,00 a R$ 300,00, limites inclusos) feitos por meios
-- eletrônicos específicos (PIX ou crédito).
SELECT p.id_pagamento,
       p.id_locacao,
       p.valor            AS valor_pago,
       p.forma_pagamento,
       p.data_pagamento
FROM   pagamentos p
WHERE  p.valor BETWEEN 100.00 AND 300.00
  AND  p.forma_pagamento IN ('PIX', 'CREDITO')
ORDER  BY p.valor DESC;


/* =====================================================================
   BLOCO B - BUSCAS TEXTUAIS COM PADRÕES
   ===================================================================== */

-- Questão 4 (a) - Busca case-insensitive com curinga [ILIKE, %]
-- Problema de negócio: o cliente pergunta "vocês têm barraca?". O
-- atendente digita o termo em maiúsculas e a busca precisa encontrar
-- o item em qualquer posição do nome, ignorando maiúsculas/minúsculas.
SELECT e.id_equipamento,
       e.nome          AS equipamento,
       e.valor_diaria  AS diaria,
       e.qtd_estoque   AS estoque
FROM   equipamentos e
WHERE  e.nome ILIKE '%BARRACA%'
ORDER  BY e.nome;

-- Questão 4 (b) - Curinga de caractere único [_]
-- Problema de negócio: auditoria de cadastro de marcas. Localiza os
-- equipamentos cuja marca tem exatamente 3 letras (3 sublinhados),
-- tamanho fixo, como "Mor".
SELECT e.id_equipamento,
       e.nome   AS equipamento,
       e.marca
FROM   equipamentos e
WHERE  e.marca LIKE '___'
ORDER  BY e.nome;


/* =====================================================================
   BLOCO C - FUNÇÕES MATEMÁTICAS E DE TEXTO
   ===================================================================== */

-- Questão 5 - Simulação numérica e arredondamentos [ROUND, TRUNC, CEIL, FLOOR]
-- Problema de negócio: a loja vai reajustar em 7,5% a diária dos
-- equipamentos disponíveis. A simulação mostra o valor original, o
-- novo valor arredondado (ROUND), cortado (TRUNC) e também o menor
-- e o maior valor inteiro (CEIL e FLOOR) para decidir qual política
-- de arredondamento usar na tabela de preços.
SELECT e.nome                                AS equipamento,
       e.valor_diaria                        AS diaria_atual,
       ROUND(e.valor_diaria * 1.075, 2)      AS reajuste_round,
       TRUNC(e.valor_diaria * 1.075, 2)      AS reajuste_trunc,
       CEIL(e.valor_diaria * 1.075)          AS reajuste_teto,
       FLOOR(e.valor_diaria * 1.075)         AS reajuste_piso
FROM   equipamentos e
WHERE  e.status = 'DISPONIVEL'
ORDER  BY e.valor_diaria DESC;


-- Questão 6 (a) - Classificação por módulo [MOD]
-- Problema de negócio: separar o catálogo em dois lotes de conferência
-- física de estoque (código par = prateleira A, código ímpar = B).
SELECT e.id_equipamento,
       e.nome AS equipamento,
       CASE WHEN MOD(e.id_equipamento, 2) = 0
            THEN 'Par - Prateleira A'
            ELSE 'Ímpar - Prateleira B'
       END    AS lote_conferencia
FROM   equipamentos e
ORDER  BY e.id_equipamento;

-- Questão 6 (b) - Sorteio de registro ativo [ORDER BY RANDOM() LIMIT 1]
-- Problema de negócio: sorteio de brinde (1 diária grátis) entre os
-- clientes ativos da loja. O resultado muda a cada execução.
SELECT c.id_cliente,
       c.nome   AS cliente_sorteado,
       c.cidade
FROM   clientes c
WHERE  c.ativo = TRUE
ORDER  BY RANDOM()
LIMIT  1;


-- Questão 7 - Concatenação, padronização e extração [CONCAT, UPPER, INITCAP, SPLIT_PART, LEFT]
-- Problema de negócio: gerar a ficha resumida do cliente para a
-- etiqueta de retirada: descrição única (CONCAT protege contra
-- telefone NULL), nome em maiúsculas, cidade padronizada com INITCAP,
-- primeiro nome (SPLIT_PART), login do e-mail e CPF parcialmente
-- mascarado (LEFT) para não expor o documento completo.
SELECT CONCAT(c.nome, ' - ', INITCAP(LOWER(c.cidade)), ' - Tel: ',
              COALESCE(c.telefone, 'não informado'))  AS ficha_cliente,
       UPPER(c.nome)                                  AS nome_maiusculo,
       SPLIT_PART(c.nome, ' ', 1)                     AS primeiro_nome,
       SPLIT_PART(c.email, '@', 1)                    AS login_email,
       LEFT(c.cpf, 3) || '.***.***-**'                AS cpf_mascarado
FROM   clientes c
ORDER  BY c.nome;


/* =====================================================================
   BLOCO D - FUNÇÕES DE DATA/HORA E FORMATAÇÃO
   ===================================================================== */

-- Questão 8 - Extração temporal e janela de período [EXTRACT, DATE_TRUNC, INTERVAL]
-- Problema de negócio: relatório das locações retiradas nos últimos
-- 30 dias, mostrando ano, mês, dia da semana (0 = domingo) e o
-- primeiro dia do mês, para analisar em que dias a loja mais aluga.
-- (As tabelas usam colunas DATE, por isso a janela é em dias.)
SELECT l.id_locacao,
       l.data_retirada,
       EXTRACT(YEAR  FROM l.data_retirada)         AS ano,
       EXTRACT(MONTH FROM l.data_retirada)         AS mes,
       EXTRACT(DOW   FROM l.data_retirada)         AS dia_semana,
       DATE_TRUNC('month', l.data_retirada)::DATE  AS inicio_do_mes
FROM   locacoes l
WHERE  l.data_retirada >= NOW() - INTERVAL '30 days'
ORDER  BY l.data_retirada;


-- Questão 9 - Tempo decorrido e projeção futura [AGE, NOW(), + INTERVAL]
-- Problema de negócio: programa de fidelidade. Mostra há quanto tempo
-- cada cliente ativo está cadastrado (AGE) e a data de renovação do
-- cadastro, projetada em 1 ano após o cadastro (data + INTERVAL).
SELECT c.nome                                          AS cliente,
       c.data_cadastro,
       AGE(NOW(), c.data_cadastro)                     AS tempo_de_cadastro,
       (c.data_cadastro + INTERVAL '1 year')::DATE     AS renovacao_cadastro
FROM   clientes c
WHERE  c.ativo = TRUE
ORDER  BY c.data_cadastro;


-- Questão 10 - Relatório gerencial formatado [INNER JOIN, TO_CHAR, LPAD, FORMAT]
-- Problema de negócio: relatório do financeiro com os pagamentos
-- recebidos. Une 3 tabelas (pagamentos, locações e clientes), padroniza
-- o código da locação com zeros à esquerda (LPAD), formata data no
-- padrão brasileiro e valor monetário (TO_CHAR com FM) e monta uma
-- linha de resumo textual com FORMAT.
SELECT 'LOC-' || LPAD(l.id_locacao::TEXT, 5, '0')           AS cod_locacao,
       c.nome                                               AS cliente,
       TO_CHAR(l.data_retirada, 'DD/MM/YYYY')               AS retirada,
       TO_CHAR(p.valor, 'FM"R$ "999G990D00')                AS valor_pago,
       FORMAT('Locação %s de %s: %s via %s em %s',
              LPAD(l.id_locacao::TEXT, 5, '0'),
              c.nome,
              TO_CHAR(p.valor, 'FM990D00'),
              p.forma_pagamento,
              TO_CHAR(p.data_pagamento, 'DD/MM/YYYY'))      AS resumo
FROM   pagamentos p
INNER  JOIN locacoes l ON l.id_locacao = p.id_locacao
INNER  JOIN clientes c ON c.id_cliente = l.id_cliente
ORDER  BY p.data_pagamento, l.id_locacao;

-- FIM DO SCRIPT
