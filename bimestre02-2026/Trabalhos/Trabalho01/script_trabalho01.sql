/* =====================================================================
   TRABALHO PRÁTICO 01 - Gestão de Banco de Dados (PostgreSQL)
   2º Bimestre / 2026
   Aluno: Kauã Cesar da Silva        RA: 007556
   Tema: Locadora de Equipamentos de Camping e Aventura ("TrilhaCerta")
   ---------------------------------------------------------------------
   JUSTIFICATIVA DA ESCOLHA DO TEMA
   O turismo de aventura e o camping crescem a cada ano, mas muita gente
   não quer (ou não pode) comprar barracas, mochilas cargueiras, fogareiros
   e outros itens caros que serão usados poucas vezes. A locação resolve
   esse problema. Escolhi este tema porque ele tem regras de negócio
   claras e ricas para modelar: controle de estoque, preço de diária,
   prazos de devolução, status de locação e formas de pagamento.

   CONTEXTUALIZAÇÃO DO NEGÓCIO
   A "TrilhaCerta" é uma loja que aluga equipamentos de camping para
   pessoas físicas. O cliente se cadastra, escolhe equipamentos de
   diferentes categorias, retira os itens por um período (diárias) e
   paga pela locação. O banco de dados controla clientes, catálogo,
   estoque, locações realizadas e pagamentos recebidos.
   ===================================================================== */

-- ---------------------------------------------------------------------
-- 0. LIMPEZA (permite executar o script várias vezes sem erro)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS pagamentos     CASCADE;
DROP TABLE IF EXISTS itens_locacao  CASCADE;
DROP TABLE IF EXISTS locacoes       CASCADE;
DROP TABLE IF EXISTS equipamentos   CASCADE;
DROP TABLE IF EXISTS categorias     CASCADE;
DROP TABLE IF EXISTS clientes       CASCADE;

-- ---------------------------------------------------------------------
-- 1. CRIAÇÃO DAS TABELAS
-- ---------------------------------------------------------------------

/* TABELA clientes
   Objetivo: guardar os dados cadastrais de quem aluga equipamentos.
   Finalidade: identificar o cliente em cada locação, permitir contato
   (e-mail/telefone) e evitar cadastros duplicados por CPF e e-mail. */
CREATE TABLE clientes (
    id_cliente     SERIAL       PRIMARY KEY,
    nome           VARCHAR(100) NOT NULL,
    cpf            CHAR(11)     NOT NULL UNIQUE,
    email          VARCHAR(100) NOT NULL UNIQUE,
    telefone       VARCHAR(15),
    cidade         VARCHAR(60)  NOT NULL,
    data_cadastro  DATE         NOT NULL DEFAULT CURRENT_DATE,
    ativo          BOOLEAN      NOT NULL DEFAULT TRUE,
    CONSTRAINT ck_clientes_cpf CHECK (cpf ~ '^[0-9]{11}$')
);

/* TABELA categorias
   Objetivo: classificar os equipamentos em grupos (barracas, cozinha...).
   Finalidade: organizar o catálogo e permitir relatórios por tipo de
   equipamento, sem repetir o nome da categoria em cada equipamento. */
CREATE TABLE categorias (
    id_categoria  SERIAL       PRIMARY KEY,
    nome          VARCHAR(50)  NOT NULL UNIQUE,
    descricao     VARCHAR(200)
);

/* TABELA equipamentos
   Objetivo: cadastrar cada item do catálogo disponível para locação.
   Finalidade: guardar preço da diária, quantidade em estoque e situação
   do item (disponível, em manutenção ou inativo). Cada equipamento
   pertence a uma categoria. */
CREATE TABLE equipamentos (
    id_equipamento  SERIAL         PRIMARY KEY,
    id_categoria    INTEGER        NOT NULL,
    nome            VARCHAR(100)   NOT NULL,
    marca           VARCHAR(50),
    valor_diaria    NUMERIC(8,2)   NOT NULL,
    qtd_estoque     INTEGER        NOT NULL DEFAULT 1,
    status          VARCHAR(15)    NOT NULL DEFAULT 'DISPONIVEL',
    CONSTRAINT fk_equip_categoria FOREIGN KEY (id_categoria)
        REFERENCES categorias (id_categoria),
    CONSTRAINT ck_equip_valor   CHECK (valor_diaria > 0),
    CONSTRAINT ck_equip_estoque CHECK (qtd_estoque >= 0),
    CONSTRAINT ck_equip_status  CHECK (status IN ('DISPONIVEL','MANUTENCAO','INATIVO'))
);

/* TABELA locacoes
   Objetivo: registrar o "cabeçalho" de cada locação feita por um cliente.
   Finalidade: controlar datas de retirada, devolução prevista e devolução
   real, além da situação (aberta, finalizada, atrasada ou cancelada).
   Um cliente pode ter várias locações. */
CREATE TABLE locacoes (
    id_locacao          SERIAL      PRIMARY KEY,
    id_cliente          INTEGER     NOT NULL,
    data_retirada       DATE        NOT NULL DEFAULT CURRENT_DATE,
    data_prevista       DATE        NOT NULL,
    data_devolucao      DATE,
    status              VARCHAR(15) NOT NULL DEFAULT 'ABERTA',
    CONSTRAINT fk_loc_cliente FOREIGN KEY (id_cliente)
        REFERENCES clientes (id_cliente),
    CONSTRAINT ck_loc_status  CHECK (status IN ('ABERTA','FINALIZADA','ATRASADA','CANCELADA')),
    CONSTRAINT ck_loc_prevista CHECK (data_prevista >= data_retirada),
    CONSTRAINT ck_loc_devolucao CHECK (data_devolucao IS NULL OR data_devolucao >= data_retirada)
);

/* TABELA itens_locacao
   Objetivo: detalhar quais equipamentos (e quantas unidades) fazem parte
   de cada locação.
   Finalidade: resolver o relacionamento N:N entre locacoes e equipamentos.
   Guarda o valor da diária cobrado na época, pois o preço do catálogo
   pode mudar depois sem alterar locações antigas. */
CREATE TABLE itens_locacao (
    id_item         SERIAL        PRIMARY KEY,
    id_locacao      INTEGER       NOT NULL,
    id_equipamento  INTEGER       NOT NULL,
    quantidade      INTEGER       NOT NULL DEFAULT 1,
    valor_diaria    NUMERIC(8,2)  NOT NULL,
    CONSTRAINT fk_item_locacao FOREIGN KEY (id_locacao)
        REFERENCES locacoes (id_locacao) ON DELETE CASCADE,
    CONSTRAINT fk_item_equip FOREIGN KEY (id_equipamento)
        REFERENCES equipamentos (id_equipamento),
    CONSTRAINT ck_item_qtd   CHECK (quantidade > 0),
    CONSTRAINT ck_item_valor CHECK (valor_diaria > 0),
    CONSTRAINT uq_item_loc_equip UNIQUE (id_locacao, id_equipamento)
);

/* TABELA pagamentos
   Objetivo: registrar os pagamentos recebidos de cada locação.
   Finalidade: controlar valor, forma de pagamento e data, permitindo
   pagamento parcelado (várias linhas para a mesma locação) e o cálculo
   do faturamento da loja. */
CREATE TABLE pagamentos (
    id_pagamento     SERIAL        PRIMARY KEY,
    id_locacao       INTEGER       NOT NULL,
    valor            NUMERIC(10,2) NOT NULL,
    forma_pagamento  VARCHAR(15)   NOT NULL,
    data_pagamento   DATE          NOT NULL DEFAULT CURRENT_DATE,
    CONSTRAINT fk_pag_locacao FOREIGN KEY (id_locacao)
        REFERENCES locacoes (id_locacao),
    CONSTRAINT ck_pag_valor CHECK (valor > 0),
    CONSTRAINT ck_pag_forma CHECK (forma_pagamento IN ('PIX','CREDITO','DEBITO','DINHEIRO'))
);

-- ---------------------------------------------------------------------
-- 2. INSERÇÃO DE DADOS (massa de dados)
-- ---------------------------------------------------------------------

INSERT INTO clientes (nome, cpf, email, telefone, cidade, data_cadastro, ativo) VALUES
('Ana Beatriz Souza',   '11122233344', 'ana.souza@email.com',    '16991110001', 'Ribeirão Preto', '2026-01-10', TRUE),
('Bruno Henrique Lima', '22233344455', 'bruno.lima@email.com',   '16991110002', 'Sertãozinho',    '2026-01-22', TRUE),
('Carla Mendes',        '33344455566', 'carla.mendes@email.com', '16991110003', 'Ribeirão Preto', '2026-02-05', TRUE),
('Diego Fernandes',     '44455566677', 'diego.f@email.com',      '16991110004', 'Jardinópolis',   '2026-02-18', TRUE),
('Eduarda Martins',     '55566677788', 'edu.martins@email.com',  '16991110005', 'Ribeirão Preto', '2026-03-03', TRUE),
('Felipe Araújo',       '66677788899', 'felipe.a@email.com',     '16991110006', 'Franca',         '2026-03-15', TRUE),
('Gabriela Rocha',      '77788899900', 'gabi.rocha@email.com',   '16991110007', 'Ribeirão Preto', '2026-04-01', TRUE),
('Henrique Duarte',     '88899900011', 'henrique.d@email.com',   '16991110008', 'Sertãozinho',    '2026-04-20', FALSE);

INSERT INTO categorias (nome, descricao) VALUES
('Barracas',     'Barracas de acampamento de diversos tamanhos'),
('Dormir',       'Sacos de dormir, colchões infláveis e travesseiros'),
('Cozinha',      'Fogareiros, panelas e utensílios para acampamento'),
('Mochilas',     'Mochilas cargueiras e de trilha'),
('Iluminação',   'Lanternas, lampiões e headlamps'),
('Mobiliário',   'Cadeiras, mesas dobráveis e redes');

INSERT INTO equipamentos (id_categoria, nome, marca, valor_diaria, qtd_estoque, status) VALUES
(1, 'Barraca Iglu 2 pessoas',        'Nautika',  45.00, 5, 'DISPONIVEL'),
(1, 'Barraca Família 6 pessoas',     'Guepardo', 95.00, 2, 'DISPONIVEL'),
(2, 'Saco de dormir -5°C',           'Echolife', 25.00, 8, 'DISPONIVEL'),
(2, 'Colchão inflável casal',        'Bestway',  20.00, 4, 'MANUTENCAO'),
(3, 'Fogareiro a gás portátil',      'Nautika',  18.00, 6, 'DISPONIVEL'),
(3, 'Kit panelas 5 peças',           'Mor',      15.00, 5, 'DISPONIVEL'),
(4, 'Mochila cargueira 60L',         'Deuter',   35.00, 4, 'DISPONIVEL'),
(5, 'Lanterna de cabeça LED',        'Tramontina',10.00,10, 'DISPONIVEL'),
(6, 'Cadeira dobrável',              'Mor',       8.00,10, 'DISPONIVEL'),
(6, 'Rede de descanso',              'Tupy',     12.00, 3, 'INATIVO');

INSERT INTO locacoes (id_cliente, data_retirada, data_prevista, data_devolucao, status) VALUES
(1, '2026-05-02', '2026-05-05', '2026-05-05', 'FINALIZADA'),
(2, '2026-05-10', '2026-05-12', '2026-05-14', 'FINALIZADA'),
(3, '2026-06-01', '2026-06-04', '2026-06-04', 'FINALIZADA'),
(1, '2026-07-15', '2026-07-20', '2026-07-20', 'FINALIZADA'),
(4, '2026-08-08', '2026-08-10', NULL,         'CANCELADA'),
(5, '2026-09-12', '2026-09-15', '2026-09-15', 'FINALIZADA'),
(6, '2026-10-05', '2026-10-08', NULL,         'ATRASADA'),
(7, '2026-10-20', '2026-10-23', '2026-10-23', 'FINALIZADA'),
(3, '2026-10-28', '2026-11-02', NULL,         'ATRASADA'),
(2, '2026-11-01', '2026-11-05', NULL,         'ABERTA');

INSERT INTO itens_locacao (id_locacao, id_equipamento, quantidade, valor_diaria) VALUES
(1, 1, 1, 45.00),
(1, 3, 2, 25.00),
(2, 2, 1, 95.00),
(2, 5, 1, 18.00),
(3, 1, 1, 45.00),
(3, 7, 2, 35.00),
(4, 2, 1, 95.00),
(4, 3, 4, 25.00),
(4, 6, 1, 15.00),
(5, 1, 1, 45.00),
(6, 7, 1, 35.00),
(6, 8, 2, 10.00),
(7, 1, 2, 45.00),
(7, 5, 1, 18.00),
(8, 9, 4, 8.00),
(8, 6, 1, 15.00),
(9, 2, 1, 95.00),
(10, 3, 2, 25.00),
(10, 8, 2, 10.00);

INSERT INTO pagamentos (id_locacao, valor, forma_pagamento, data_pagamento) VALUES
(1, 285.00, 'PIX',      '2026-05-02'),
(2, 226.00, 'CREDITO',  '2026-05-10'),
(3, 345.00, 'PIX',      '2026-06-01'),
(4, 600.00, 'CREDITO',  '2026-07-15'),
(4, 450.00, 'DINHEIRO', '2026-07-20'),
(6, 165.00, 'DEBITO',   '2026-09-12'),
(7, 100.00, 'PIX',      '2026-10-05'),
(8, 100.00, 'PIX',      '2026-10-20'),
(9, 200.00, 'CREDITO',  '2026-10-28'),
(10, 280.00,'PIX',      '2026-11-01');

-- ---------------------------------------------------------------------
-- 3. CONSULTAS (SELECT)
-- ---------------------------------------------------------------------

-- 3.1 INNER JOIN + filtro: locações que ainda não foram devolvidas,
--     com o nome do cliente e sua cidade.
SELECT l.id_locacao, c.nome AS cliente, c.cidade,
       l.data_retirada, l.data_prevista, l.status
FROM   locacoes l
JOIN   clientes c ON c.id_cliente = l.id_cliente
WHERE  l.data_devolucao IS NULL
  AND  l.status IN ('ABERTA','ATRASADA')
ORDER  BY l.data_prevista;

-- 3.2 JOIN de 3 tabelas: equipamentos com o nome de sua categoria,
--     apenas os disponíveis com diária acima de R$ 15,00.
SELECT e.nome AS equipamento, cat.nome AS categoria,
       e.marca, e.valor_diaria, e.qtd_estoque
FROM   equipamentos e
JOIN   categorias cat ON cat.id_categoria = e.id_categoria
WHERE  e.status = 'DISPONIVEL'
  AND  e.valor_diaria > 15
ORDER  BY e.valor_diaria DESC;

-- 3.3 GROUP BY: quantidade de equipamentos e estoque total por categoria.
SELECT cat.nome AS categoria,
       COUNT(e.id_equipamento) AS qtd_modelos,
       SUM(e.qtd_estoque)      AS estoque_total
FROM   categorias cat
LEFT   JOIN equipamentos e ON e.id_categoria = cat.id_categoria
GROUP  BY cat.nome
ORDER  BY estoque_total DESC;

-- 3.4 GROUP BY + SUM + JOIN: total pago por cliente (faturamento por cliente).
SELECT c.nome AS cliente,
       COUNT(DISTINCT l.id_locacao) AS qtd_locacoes,
       SUM(p.valor)                 AS total_pago
FROM   clientes c
JOIN   locacoes l  ON l.id_cliente = c.id_cliente
JOIN   pagamentos p ON p.id_locacao = l.id_locacao
GROUP  BY c.nome
ORDER  BY total_pago DESC;

-- 3.5 GROUP BY + HAVING: formas de pagamento com mais de R$ 300,00 recebidos.
SELECT forma_pagamento,
       COUNT(*)   AS qtd_pagamentos,
       SUM(valor) AS total_recebido
FROM   pagamentos
GROUP  BY forma_pagamento
HAVING SUM(valor) > 300
ORDER  BY total_recebido DESC;

-- 3.6 Equipamentos mais alugados (soma das unidades), ignorando cancelamentos.
SELECT e.nome AS equipamento,
       SUM(i.quantidade) AS unidades_alugadas
FROM   itens_locacao i
JOIN   equipamentos e ON e.id_equipamento = i.id_equipamento
JOIN   locacoes l     ON l.id_locacao = i.id_locacao
WHERE  l.status <> 'CANCELADA'
GROUP  BY e.nome
ORDER  BY unidades_alugadas DESC
LIMIT  5;

-- 3.7 Valor total de cada locação (diárias x quantidade x dias),
--     com cálculo de dias usando as datas de retirada e prevista.
SELECT l.id_locacao, c.nome AS cliente,
       (l.data_prevista - l.data_retirada) AS dias,
       SUM(i.quantidade * i.valor_diaria * (l.data_prevista - l.data_retirada)) AS valor_total
FROM   locacoes l
JOIN   clientes c      ON c.id_cliente = l.id_cliente
JOIN   itens_locacao i ON i.id_locacao = l.id_locacao
GROUP  BY l.id_locacao, c.nome, l.data_retirada, l.data_prevista
ORDER  BY valor_total DESC;

-- 3.8 LEFT JOIN: clientes que NUNCA fizeram uma locação.
SELECT c.nome, c.cidade, c.ativo
FROM   clientes c
LEFT   JOIN locacoes l ON l.id_cliente = c.id_cliente
WHERE  l.id_locacao IS NULL;

-- 3.9 Filtros condicionais (LIKE + BETWEEN): locações de maio a julho
--     de clientes cujo nome começa com A ou B.
SELECT l.id_locacao, c.nome, l.data_retirada, l.status
FROM   locacoes l
JOIN   clientes c ON c.id_cliente = l.id_cliente
WHERE  l.data_retirada BETWEEN '2026-05-01' AND '2026-07-31'
  AND  (c.nome LIKE 'A%' OR c.nome LIKE 'B%');

-- 3.10 Subconsulta: equipamentos com diária acima da média do catálogo.
SELECT nome, valor_diaria
FROM   equipamentos
WHERE  valor_diaria > (SELECT AVG(valor_diaria) FROM equipamentos)
ORDER  BY valor_diaria DESC;

-- FIM DO SCRIPT
