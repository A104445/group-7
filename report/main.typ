#import "cover.typ": cover
#import "template.typ": *

#show: project

#cover("", (
    (name: "Alexandre Miranda", number: "pg61507"),
  (name: "João Cunha", number: "pg60272"),
  (name: "João Macedo", number: "pg60274"),
  (name: "Mário Silva", number: "pg60282")),
  "janeiro, 2026")

#set page(numbering: "i", number-align: center)
#counter(page).update(1)

#show outline: it => {
    show heading: set text(size: 18pt)
    it
}

#{
  show outline.entry.where(level: 1): it => {
    v(5pt)
    strong(it)
  }

  outline(
    title: [Índice], 
    indent: auto, 
  )
}

#v(-0.4em)
#outline(
  title: none,
  target: figure.where(kind: "attachment"),
  indent: n => 1em,
)

#outline(
  title: [Lista de Figuras],
  target: figure.where(kind: image),
)

#outline(
  title: [Lista de Tabelas],
  target: figure.where(kind: table),
)

#set page(numbering: "1", number-align: center)
#counter(page).update(1)

= Introdução

No âmbito da Unidade Curricular de Administração de Bases de Dados, este relatório descreve o processo de otimização e avaliação de desempenho de um sistema de gestão de dados em PostgreSQL. O projeto simula um cenário real de utilização intensiva de uma plataforma de gestão de repositórios de código (“GitBench”), utilizando um _dataset_ de metadados extraído do GitHub.

O objetivo principal deste trabalho prático é maximizar a eficiência do sistema perante dois tipos distintos de carga de trabalho: uma carga analítica (OLAP), caracterizada por consultas complexas de agregação e análise temporal, e uma carga transacional (OLTP), que simula operações concorrentes de _backend_, como criação de repositórios, gestão de _tickets_ e interação de utilizadores.

O desenvolvimento do trabalho ocorreu numa infraestrutura computacional fixa na Google Cloud, numa instância N2 com 8 vCPUs, 16 GB de RAM e 500 GB de armazenamento SSD.

= Carga Analítica

== Interrogação Analítica 1

=== Desempenho _baseline_
A primeira interrogação analítica (Q1) procura identificar os 100 _tickets_ com maior tempo de encerramento (_merged/closed_) para cada tipo de _ticket_ (_issue_ e _pull request_). Estes 100 _tickets_ têm ainda de cumprir certas condições para serem considerados.

#figure(
  block(
    fill: luma(240),
    inset: 8pt,
    ```sql
    SELECT repository_id, ticket_id, created_by, type, title, time_to_close
    FROM (
        SELECT t.repository_id, t.ticket_id, t.created_by, t.type, t.title, t.time_to_close,
            rank() OVER(PARTITION BY type ORDER BY time_to_close desc) AS rank
        FROM (
            SELECT repository_id, ticket_id, created_by, type,
                closed_at - opened_at AS time_to_close, title
            FROM ticket
            WHERE (status = 'merged' OR status = 'closed')
                AND length(data) > 300
                AND (title || data) LIKE '%perf%'
        ) t
        JOIN repository r ON r.id = t.repository_id
        JOIN users u ON u.username = t.created_by
        WHERE r.owner <> u.username
            AND NOT r.is_archived
    )
    WHERE rank <= 100
    ORDER BY 4, 6 DESC;
    ```
  ),
  caption: [Código SQL da _query_ Q1 (versão original).]
) <Q1-base>
#v(7pt)
Esta _query_ consiste em 4 fases principais:

- *Filtragem inicial*:

Nesta primeira fase, a subquery mais interna filtra os _tickets_ cujo campo `data` apresenta um comprimento superior a 300 caracteres, que se encontrem no estado `closed` ou `merged`, e nos quais a palavra `perf` esteja presente na concatenação do `title` com `data`. Nesta etapa, calcula-se também o `time_to_close`, que será utilizado posteriormente.

- *Agregação de dados:*

Com a lista de _tickets_ já filtrada, é realizado um ```sql JOIN``` com as chaves primárias das tabelas `repository` e `users`, com o objetivo de remover os tickets criados pelos _owners_ do respetivo repositório, bem como os associados a repositórios arquivados.

- *Separação e _Ranking_:*

Já com os dados limpos e filtrados com a lógica de negócio pretendida, utilizamos uma _window function_ para dar um número a cada ticket que tenha passado a fase de filtragem, com base no `time_to_close` calculado na primeira fase. Este processo é realizado de forma independente para cada valor de `type`, garantindo que cada tipo de _ticket_ possui a sua própria numeração.

- *Filtragem final e Ordenação:*

Por fim, são selecionados os 100 _tickets_ com pior desempenho, tanto do tipo `issue` como do tipo `pull_request` (visto que cada tipo possui uma numeração independente, o resultado total corresponde a 200 _tickets_ com ```sql WHERE rank <= 100```), e ordenamos em ordem ao `type` e ao `time_to_close`.

Com o objetivo de ter uma comparação base, foram medidos os tempos da _query_ original, correndo 3x um _script_ que repete a _query_ 5x.

#align(
    center,
    table(
    columns: (auto,auto),
    align: (center,center),
    inset:8pt,
    stroke:0.5pt,
    [*Nº Execução*], [*tempo médio (s)*],
    [1], [12.585 s],
    [2], [12.584 s],
    [3], [12.570 s],
  ), 
)

=== Análise do Plano de Execução (_baseline_)
Na @Q1-explainAnalyze apresenta-se o plano de execução da Q1, obtido através do comando ```sql EXPLAIN ANALYZE``` e analisado com o auxílio da ferramenta *explain.dalibo.com*.
#figure(
  image("images/Q1_ExplainAnalyze.png"),
  caption: [Plano de Execução Q1 (versão original).]
) <Q1-explainAnalyze>
#v(7pt)
- *Gargalo Principal - Estratégia de processamento (Agregação):*

Como podemos ver na @Q1-explainAnalyze, a causa predominante da lentidão na execução da _query_ em análise é o _Parallel Seq Scan_ dentro de um _Nested Loop_, onde o volume de dados (\~1M de linhas) causa uma demora de 6.3s no processamento dos dados provenientes da tabela _tickets_. Isto evidencia uma limitação na estrutura da _query_, que processa um volume muito elevado de dados apenas para descartar a maioria deles na fase de filtragem com o ```sql WHERE rank <= 100``` após a _window function_ ```sql rank() OVER(PARTITION BY type ORDER BY time_to_close desc)```.

Isto afeta também os _Index Scans_, que apesar de individualmente serem rápidos, acabam por atrasar a query ao demorar \~3s cada (_Index Scan repository_ e _Index Only Scan users_) e provoca um _memory spill_ (external sort), fazendo com que o PostgreSQL passe a realizar leituras e ordenações em disco a partir do momento em que o limite de memória disponível (`work_mem`) é atingido.

- *Outros problemas de _performance_:*

O cálculo constante da variável `time_to_close`, bem como o processamento e a separação dos dados por cada valor de `type`, também contribuem para os tempos observados na tabela de resultados. Este processamento pode ser evitado por completo com algumas mudanças no schema e a criação de alguns índices.

=== Indexação Parcial `(type,duration desc)`

Com o objetivo de mitigar o custo de execução _baseline_, foi abordada a componente mais dispendiosa da _query_. Para isso, foram realizadas algumas alterações na tabela `ticket`, que visam simplificar e reestruturar a filtragem nesta tabela.

Neste caso, foi criado um índice parcial composto que reflete a ordem de classificação exigida pela Q1. Este índice é designado como parcial, uma vez que apenas abrange os registos que satisfazem a condição ```sql WHERE status IN ('merged','closed')```. Foi tomada a decisão de apenas indexar linhas que cumpram esses quesitos para diminuir o tamanho do índice, maximizando a performance de leitura e diminuindo a perda de performance de futuras _queries_ transacionais.


#block(
    fill: luma(240),
    inset: 8pt,
    ```sql 
CREATE INDEX idx_ticket_analytic_rank 
ON ticket (type, duration DESC)
WHERE status IN ('merged', 'closed');
  ```
)

Este índice permite que os dados aos quais vamos aceder já estejam ordenados, diminuindo assim algum custo na zona mais crítica. No entanto, para tirar partido desta otimização foi necessário reestruturar a _query_ em si.

=== Reestruturação da Lógica de Agregação

A _query_ original sofria em grande parte por causa de filtragem tardia. Lia cerca de 1 milhão de linhas, ordenava-as (muitas vezes em disco graças aos _memory slips_), calculava o `RANK` para todas, e só no final descartava a maioria dos dados.

Para resolver isto, a lógica foi invertida utilizando ```sql CROSS JOIN LATERAL```. Em vez de processar o conjunto de dados inteiro de uma só vez, a nova _query_ itera sobre os tipos de tickets conhecidos e, para cada tipo, consulta o índice para obter apenas os 100 primeiros registos (pré-ordenados como mencionado anteriormente).

Para não atrasar a pesquisa com um ```sql SELECT DISTINCT``` à tabela `ticket` inteira apenas para ir buscar os diferentes tipos, foi realizada a seguinte alteração no _schema_:

#block(
  fill: luma(240),
  inset: 8pt,
  ```sql
CREATE TYPE ticket_type_enum AS ENUM ('issue', 'pull_request');
  
CREATE TABLE ticket (
    repository_id integer,
    ticket_id integer,
    created_by varchar,
    type ticket_type_enum,
    status varchar,
    opened_at timestamp,
    closed_at timestamp,
    title varchar,
    data varchar,
    PRIMARY KEY (repository_id, ticket_id)
);
  ```
)

Isto garante a utilização de valores fixos na filtragem pelo `type`, o que nos poupa percorrer milhares de linhas de uma tabela para ir buscar alguns tipos. Os tipos do ```sql ENUM``` foram recolhidos através da seguinte _query_:

#block(
  fill: luma(240),
  inset: 8pt,
  ```sql
SELECT DISTINCT type FROM ticket;
  ```
)
#pagebreak()
Após esta alteração, partimos então para a reestruturação. O resultado final foi:
#figure(
  block(
    fill: luma(240),
    inset: 8pt,
    ```sql
  SELECT 
       top_tickets.repository_id,
       top_tickets.ticket_id,
       top_tickets.created_by,
       top_tickets.type,
       top_tickets.title,
       top_tickets.time_to_close
   FROM (
       VALUES 
           ('issue'::ticket_type_enum), 
           ('pull_request'::ticket_type_enum)
   ) AS types(type)
   CROSS JOIN LATERAL (
       SELECT 
           t.repository_id, t.ticket_id, t.created_by, t.type, t.title, 
           t.duration as time_to_close
       FROM ticket t
       JOIN repository r ON r.id = t.repository_id
       JOIN users u ON u.username = t.created_by
       WHERE 
           t.type = types.type
           AND t.status IN ('merged', 'closed')
           AND length(t.data) > 300
           AND (t.title || t.data) LIKE '%perf%'
           AND r.owner <> u.username
           AND NOT r.is_archived
       ORDER BY t.duration DESC
       LIMIT 100
   ) top_tickets
   ORDER BY 4, 6 DESC;
    ```
  ),
  caption: [Código SQL da Q1 (versão otimizada).]
)
#v(7pt)
Esta abordagem revela-se eficiente, funcionando conceptualmente como um “ciclo for” ao nível da base de dados:

#h(1em)*1.* Seleciona o tipo *`issue`*.

#h(1em)*2.* Percorre o índice *`idx_ticket_analytic_rank`* e para imediatamente após encontrar 100 registos válidos (isto funciona pois o índice pré-ordena os dados).

#h(1em)*3.* Repete o processo para *`pull_request`*.

=== Resultados Finais

A combinação do índice ordenado com a cláusula ```sql LIMIT``` dentro do ```sql LATERAL JOIN``` permitiu transformar uma leitura sequencial massiva (_Seq Scan_) numa leitura indexada de precisão (_Index Scan_).

#figure(image("images/Q1_results.png"), caption: [Plano de Execução da Q1 (versão otimizada)])<q1_exec_plan_results>

Como se observa em *@q1_exec_plan_results*, o tempo de execução reduziu-se de aproximadamente 12.5s para valores na ordem dos milissegundos, uma vez que a base de dados agora lê apenas cerca de 200 a 300 linhas do disco, em vez de \~1 milhão.

De seguida, apresentam-se os resultados do tempo médio (s) para a Q1 otimizada, com o mesmo _script_ utilizado para obter os resultados _baseline_. A melhoria de performance é superior a 800×.

#figure(
  table(
    columns: (auto, auto, auto, auto),
    inset: 10pt,
    align: center,
    [*N.º execução*], [*tempo base (s)*], [*tempo final (s)*], [*melhoria*],
    [1], [12.585 s], [0.015 s], [~839x],
    [2], [12.584 s], [0.015 s], [~839x],
    [3], [12.570 s], [0.015 s], [~838x],
  ),
  caption: [Comparação de desempenho entre a versão _baseline_ e a versão otimizada.]
)

=== Comparação com DuckDB

Por fim, comparou-se a solução otimizada no PostgreSQL com a execução da query original no DuckDB, utilizando o mesmo dataset.

\

#figure( 
  table( 
    columns: (auto, auto, auto, auto), 
    inset: 8pt, 
    stroke: 0.5pt, 
    table.header( 
    [*N.ºexecução*], [*PostgreSQL* \ (otimizado)], [*DuckDB* \ (sem otimização)], [*diferença*] ), 
    "1", "0.015 s", "2.777 s", 
    text(fill: green)[PG -99.5%], 
    "2", "0.015 s", "2.727 s",
    text(fill: green)[PG -99.5%], 
    "3", "0.015 s", "2.754 s",
    text(fill: green)[PG -99.5%], 
  ), 
  caption: [Comparação de desempenho Q1: PostgreSQL otimizado vs. DuckDB.] 
) <tab:comparacao-q1>
\
A análise dos resultados revela uma disparidade significativa, com o PostgreSQL a ser aproximadamente 180 vezes mais rápido que o DuckDB. Esta diferença ilustra uma distinção fundamental entre as arquiteturas dos dois sistemas para este tipo de consulta específica:

*1. PostgreSQL: *

Graças à estratégia de _Index Scan_ combinada com o ```sql LATERAL```, o PostgreSQL acede diretamente às 100 entradas necessárias no índice e ignora os restantes milhões de registos.

\
*2. DuckDB (Column-Store):*

O DuckDB é otimizado para agregações massivas, lendo colunas inteiras de forma vetorial. No entanto, para resolver uma _query_ de ```sql RANK()``` e ```sql LIMIT```, o DuckDB é forçado a ler e processar a totalidade da coluna `type` e de calcular sempre o `time_to_close` para determinar a ordem correta antes de poder descartar os dados. Sem um índice ordenado (como a B-Tree do Postgres), o DuckDB paga o custo de processar o _dataset_ inteiro para extrair apenas uma pequena fração dos dados.

Em conclusão, embora o DuckDB seja geralmente mais eficiente em leituras completas de tabelas (_Full Scans_), o PostgreSQL demonstra uma vantagem clara em cenários de elevada seletividade quando devidamente indexado e otimizado.
#pagebreak()
== Interrogação Analítica 2

=== Desempenho _baseline_

A segunda interrogação analítica (Q2) identifica os 25 repositórios mais populares de um determinado mês, com base no número de estrelas recebidas. Adicionalmente, a consulta lista as três linguagens de programação predominantes em cada repositório.

#figure(
  block(
    fill:luma(240),
    inset:8pt,
        ```sql
    SELECT id, full_name, languages, count
    FROM (
        SELECT *, rank() OVER(PARTITION BY month ORDER BY count DESC) AS rank
        FROM (
            SELECT r.id AS id,
                r.owner || '/' || r.name AS full_name,
                date_trunc('month', s.starred_at) AS month,
                l.languages,
                count(s.repository_id) AS count
            FROM repository r
            LEFT JOIN star s ON s.repository_id = r.id
            LEFT JOIN (
                SELECT rl.repository_id, (array_agg(l.name ORDER BY rl.size DESC))[:3] AS languages
                FROM repository_languages rl
                JOIN language l ON l.id = rl.language_id
                GROUP BY 1
            ) l ON l.repository_id = r.id
            GROUP BY 1, 2, 3, 4
        )
    )
    WHERE rank <= 25
        AND month = '2024-12-01'
    ORDER BY count DESC;
    ```
  ),
  caption: [Código SQL da _query_ Q2 (versão original).]
) <Q2-base>
#v(7pt)
A lógica da consulta consiste em três etapas principais:

1. *Agregação de estrelas e linguagens:*
Para cada repositório (`repository`), a _query_ contabiliza o número de estrelas (```sql count(s.repository_id)```) por mês e agrega as linguagens de programação mais relevantes (```sql array_agg(l.name ORDER BY rl.size DESC)[:3]```)


2. *Classificação por popularidade mensal:*
Utilizando a função ```sql rank() OVER(PARTITION BY month ORDER BY count DESC)```, os repositórios são classificados em cada mês de acordo com o número de estrelas.

3. *Filtragem dos top 25 por mês:*
Por fim, a consulta devolve apenas os repositórios com ```sql rank <= 25``` e do mês de referência (`month = "2024-12-01"`), ordenados pelo número de estrelas em ordem decrescente.

A versão original apresentou tempos de execução elevados devido à necessidade de processar dados de todos os meses antes de filtrar.
#pagebreak()
A tabela seguinte resume os tempos médios obtidos:

#table(
  columns: (auto,auto),
  align: (center,center),
  inset:8pt,
  stroke:0.5pt,
  [*argumento (mês)*], [*tempo médio (s)*],
  [`2024-12-01`], [16.921 s],
  [`2024-11-01`], [15.255 s],
  [`2024-10-01`], [15.144 s],
) <q2-baseline-times>

=== Análise do Plano de Execução (_baseline_)

O plano de execução revela que a estratégia adotada pelo otimizador sofre de ineficiências estruturais significativas, como está retratado na seguinte imagem extraída do *explain.dalibo.com*, resultando num tempo total de execução de aproximadamente 15.7 segundos. 

#figure( 
  image("images/Q2 inicial.png",
    height: 70%,),
  caption: [Plano de execução inicial da Q2] 
) <fig:Q2-final>

#pagebreak()
A análise dos nós permite identificar hierarquicamente os problemas:

1. *Gargalo principal – agregação global e leitura excessiva:*
A causa predominante da lentidão reside na estratégia de "Filtragem Tardia" (_Late Filtering_).
O nó `Finalize GroupAggregate` (e os seus processos filhos `Partial GroupAggregate`) processa a contagem de estrelas para *todos* os repositórios da base de dados, abrangendo todo o histórico temporal.
O plano mostra que o filtro `WHERE month = '2024-12-01'` e o limite `rank <= 25` são aplicados apenas *após* o processamento pesado de milhões de linhas. Este comportamento obriga o CPU a realizar cálculos de agregação complexos em dados que serão descartados imediatamente a seguir.

2. *Gargalo secundário – extravasamento de memória (_disk spill_):*
Devido ao enorme volume de dados gerado pela agregação global, a memória de trabalho alocada (`work_mem`) foi insuficiente para realizar a ordenação em RAM.
O nó `Sort`, necessário para a função `rank()`, forçou a escrita de 61 MB em disco:

*_Sort Method_:* `external merge Disk: 61152kB`.

Escrever e ler 61 MB de dados temporários no disco introduz uma latência significativa de I/O, bloqueando o pipeline de execução enquanto os dados são serializados e deserializados.

3. *Impacto no I/O (_buffers_):*
A ineficiência da estratégia reflete-se no consumo massivo de largura de banda de armazenamento:
- *leituras físicas (_read_):* foram lidas 498.887 páginas do disco. Considerando páginas de 8kB, isto equivale a transferir *~4 GB de dados* do disco para a memória para resolver uma única consulta.
- *leituras lógicas (_shared hit_):* o valor de ~27 milhões de _hits_ na cache indica que o CPU teve de revisitar as mesmas páginas de memória repetidamente para processar as junções e agregações não otimizadas.

Em conclusão, a query sofre de um problema de escala: o custo de execução cresce linearmente com o tamanho total da base de dados, independentemente de estarmos a pedir dados de apenas um mês.

=== Estratégias de Otimização Implementadas

A _query_ original apresentava tempos de execução elevados devido ao cálculo de agregações e junções (JOINs) em todo o conjunto de dados antes da filtragem. A versão otimizada reduziu o tempo de execução drasticamente (de \~15s para \~1s) através de três alterações estruturais:

1. *Filtragem SARGable (Search ARGumentable):*
A cláusula original `date_trunc('month', s.starred_at)` impedia o uso de índices, forçando uma leitura sequencial (Seq Scan).
Substituiu-se por um intervalo de datas explícito (`starred_at >= X AND starred_at < Y`), permitindo que o PostgreSQL utilizasse o índice para saltar diretamente para os registos relevantes.

2. *Index Only Scan (índice de cobertura):*
Criou-se o índice `idx_star_optimize` com a data como primeira coluna para suportar o filtro e o ID como segunda para a contagem:

#block(
  fill:luma(240),
  inset:8pt,
  ```sql
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_star_optimize 
ON star (starred_at, repository_id);
```)

Isto permite que o banco responda à agregação lendo apenas a estrutura do índice em memória (_Index Only Scan_), eliminando a necessidade de aceder à tabela principal (_Heap Fetch_).

- *3. Adiamento de joins e indexação ordenada:*
Foi utilizada uma CTE para isolar os ID's dos repositórios no top 25 antes de qualquer join. Para a subconsulta de linguagens, criou-se um índice que já incorpora a ordenação necessária.

#block( fill:luma(240), inset:8pt,

```SQL
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_repo_lang_optimize 
ON repository_languages (repository_id, size DESC);
```)

Isto permitiu que a pesquisa do top 3 de linguagens fosse instantânea, uma vez que o índice já fornece os dados ordenados por size DESC, evitando operações de ordenação dispendiosas.

A versão final da _query_ ficou estruturada da seguinte forma:

#figure(
  block(
    fill:luma(240),
    inset:8pt,
        ```sql
    WITH top_stars_filtered AS (
        SELECT 
            repository_id, 
            count(*) AS count
        FROM star s
        WHERE s.starred_at >= '2024-12-01'::date 
          AND s.starred_at < ('2024-12-01'::date + INTERVAL '1 month')
        GROUP BY repository_id
        ORDER BY count DESC
        LIMIT 25
    )
    SELECT 
        t.repository_id AS id,
        r.owner || '/' || r.name AS full_name,
        '2024-12-01 00:00:00+00'::timestamptz AS month,
        (
            SELECT (array_agg(l.name ORDER BY rl.size DESC))[:3]
            FROM repository_languages rl
            JOIN language l ON l.id = rl.language_id
            WHERE rl.repository_id = t.repository_id
        ) AS languages,
        t.count
    FROM top_stars_filtered t
    JOIN repository r ON r.id = t.repository_id
    ORDER BY t.count DESC;
    ```
  ),
  caption: [Código SQL da _query_ Q2 (versão otimizada).]
) <Q2-base>
#pagebreak()
=== Resultados Finais

O impacto das otimizações foi significativo. A utilização do _Index Only Scan_ eliminou a leitura da tabela star do disco e o _Deferred Join_ evitou o processamento desnecessário de linguagens.

#figure( 
  image("images/Q2 otimizada.png",
    height:50%,), 
  caption: [Plano de execução final da Q2] 
) <fig:Q2-final>
#v(7pt)
A tabela seguinte compara os tempos médios entre a versão original e a versão otimizada:

#figure(
  table(
    columns: (auto, auto, auto),
    align: (center, center, center),
    inset: 8pt,
    stroke: 0.5pt,
    table.header(
      [*agrumento (mês)*], 
      [*tempo base* (s)], 
      [*tempo otimizado* (s)]
    ),
    [2024-12-01], [16.921], [*1.025*],
    [2024-11-01], [15.255], [*0.861*],
    [2024-10-01], [15.144], [*0.795*],
  ),
  caption: [Comparação de tempos de execução: _baseline_ vs. versão otimizada.]
) <Q2-results>
#v(7pt)
A redução de \~15.7s para \~0.9s representa uma melhoria de performance superior a 17×.

=== Comparação com DuckDB

Os testes no DuckDB foram executados sobre o mesmo conjunto de dados para comparar a abordagem  otimizada do PostgreSQL contra a performance da query original no DuckDB. A @tab:comparacao-q2 apresenta os resultados obtidos.

#figure(
  table(
    columns: (auto, auto, auto, auto),
    inset: 8pt, 
    stroke: 0.5pt,
    table.header(
      [*argumento*],
      [*PostgreSQL* \ (otimizado)],
      [*DuckDB* \ (sem otimização)],
      [*diferença*]
    ),
    "2024-12-01", "1.025 s", "7.605 s", text(fill: green)[PG -86.5%],
    "2024-11-01", "0.861 s", "7.637 s", text(fill: green)[PG -88.7%],
    "2024-10-01", "0.795 s", "7.604 s", text(fill: green)[PG -89.5%],
  ),
  caption: [Comparação de desempenho: PostgreSQL otimizado vs. DuckDB.]
) <tab:comparacao-q2>
#v(7pt)
A análise dos resultados revela que o PostgreSQL otimizado é entre *7 a 9 vezes mais rápido* que o DuckDB neste cenário. A diferença de comportamento explica-se pelas estruturas de acesso aos dados:

1. *PostgreSQL (_Index Scan_ + Agregação):*
O tempo de execução do PostgreSQL (0.8s a 1.0s) é dominado pelo custo de CPU da operação `HashAggregate`. Embora o índice `idx_star_optimize` permita isolar rapidamente o mês correto (evitando ler a tabela toda), o banco ainda precisa de contar e agrupar individualmente cerca de 2 milhões de registos, o que consome o tempo observado.

2. *DuckDB (_Columnar Scan_):*
O DuckDB, sem um índice na coluna de datas, é forçado a varrer a coluna inteira para filtrar os registos do mês desejado. Embora a sua arquitetura colunar seja eficiente, o custo de ler e filtrar dezenas de milhões de datas supera o custo da agregação focada que o PostgreSQL consegue fazer graças ao índice.

Em suma, embora o DuckDB apresente um desempenho nativo robusto para cargas analíticas, os resultados demonstram que a indexação direcionada do PostgreSQL permite obter vantagens claras em cenários de elevada seletividade temporal.
#pagebreak()
== Interrogação Analítica 3

A terceira interrogação analítica (Q3) visa agregar diferentes tipos de eventos (_commits_, _tickets_, criação de utilizadores, etc.) ocorridos num determinado intervalo temporal.. Estes eventos são posteriormente agrupados em intervalos regulares de tempo e contabilizados.

=== Desempenho baseline

A consulta original é apresentada na seguinte imagem:

#figure(
  block(
    fill:luma(240),
    inset:8pt,
    ```sql
SELECT date_bin('15 minutes', date, '2009-01-01') AS interval, event, count(*) AS count
FROM (
    SELECT 'commit' AS event, created_at AS date
    FROM commit
    UNION ALL
    SELECT 'ticket_opened', opened_at
    FROM ticket
    UNION ALL
    SELECT 'ticket_closed', closed_at
    FROM ticket
    WHERE closed_at IS NOT NULL
    UNION ALL
    SELECT 'repository', created_at
    FROM repository
    UNION ALL
    SELECT 'user', created_at
    FROM users
    UNION ALL
    SELECT 'star', starred_at
    FROM star
)
WHERE date BETWEEN '2022-01-01' AND '2025-01-01'
GROUP BY 1, 2
ORDER BY 1, 2;
    ```
  ),
  caption: [Código SQL da _query_ Q3(versão original).]
) <Q3-base>
#v(7pt)
Esta versão reúne vários eventos fazendo uso do ```sql UNION ALL```. Depois disso, filtra-os e agrupa-os em blocos de 15 minutos.

As medições iniciais evidenciaram constrangimentos de desempenho significativos, mais notoriamente no longo tempo de execução. Na seguinte tabela estão representadas as médias dos tempos de execução (média obtida através de10 execuções) para diversos intervalos de tempo e com diferentes bins.

#align(center,
 table(
  columns: (auto,auto,auto),
  align: (center,center),
  inset:8pt,
  stroke:0.5pt,
  [*intervalo de tempo*],[*bin*] ,[*tempo médio(s)*],
  [`2022-01-01 a 2025-01-01`], [`15 minutos`], [35.122 s],
  [`2022-01-01 a 2025-01-01`], [`60 minutos`], [34.023 s],
  [`2020-01-01 a 2020-06-01`], [`15 minutos`], [32.222 s],
) )<Q3-baseline-times>

=== Análise do plano de execução

Para encontrarmos os principais entraves a um melhor funcionamento das pesquisas, gerou-se e analisou-se o plano de execução através do _EXPLAIN ANALYZE_.


#figure(
  image("images/primeira.png"),
  caption: [Plano de Execução Q3 (versão original).]
) <Q3-explainAnalyze>
#v(7pt)
- *Gargalo Principal - Estratégia de processamento (Agregação):*


O plano mostra que o desempenho é dominado por múltiplas operações de _Parallel Seq Scan_ sobre todas as tabelas envolvidas no ```sql UNION ALL```, especialmente as tabelas maiores (`star`, `commit` e `users`). Cada uma delas percorre milhões de linhas apenas para aplicar filtros de datas antes de alimentar o _Parallel Append_.

Pontos principais observados:

1.* Gargalo principal*: um _Parallel Seq Scan_ na tabela star que produz 15 807 249 linhas por nó com um tempo de 3815 ms a 10211 ms por processo.

#figure(
  block(
    fill: luma(240),
    inset: 8pt,
    ```text
Parallel Seq Scan on star … rows=5350832 … actual rows=15807249
    ```
  ),
) <Q3-1>

2. *Gargalos Secundários*: as restantes tabelas são igualmente percorridas de forma integral e, devido ao seu elevado volume de dados, contribuem significativamente para o aumento do tempo total de execução.

#figure(
  block(
    fill: luma(240),
    inset: 8pt,
    ```text
Parallel Seq Scan on commit ...
actual rows=4516611 Rows Removed by Filter: 1911960
    ```
  ),
) <Q3-2>

#figure(
  block(
    fill: luma(240),
    inset: 8pt,
    ```text
Parallel Seq Scan on users ...
actual rows=1898754 Rows Removed by Filter: 8101250
    ```
  ),
) <Q3-3>

#figure(
  block(
    fill: luma(240),
    inset: 8pt,
    ```text
Parallel Seq Scan on ticket ...
actual rows=3224998 Rows Removed by Filter: 1775002

    ```
  ),
) <Q3-4>

=== Indexação de colunas

Foram criados índices sobre as colunas temporais (`created_at`, `opened_at`, `closed_at`, `starred_at`) de todas as tabelas envolvidas na query uma vez que o plano de execução mostrava vários _Parallel Seq Scan_ a milhões de linhas apenas para aplicar filtros de data.
#pagebreak()
Os índices criados evitam leituras completas das tabelas, diminuindo assim o custo das operações.

#figure(
  block(
    fill: luma(240),
    inset: 8pt,
    ```sql
CREATE INDEX idx_commit_created_at
    ON commit (created_at);

CREATE INDEX idx_repository_created_at
    ON repository (created_at);

CREATE INDEX idx_star_starred_at
    ON star (starred_at);

CREATE INDEX idx_ticket_closed_at
    ON ticket (closed_at);

CREATE INDEX idx_ticket_opened_at
    ON ticket (opened_at);

CREATE INDEX idx_users_created_at
    ON users (created_at);
    ```
  ), caption: [Índices criados] ,
)  <Q3-índices> 
#v(7pt)
=== Reestruturação da lógica da pesquisa
Na versão original, o filtro `WHERE date BETWEEN ...` era aplicado apenas após a união de todas as tabelas, forçando o processamento de um volume excessivo de dados que seriam descartados posteriormente.

A otimização consistiu em aplicar os filtros temporais e a agregação diretamente em cada _subquery_, *antes* do `UNION ALL`. Esta técnica reduz drasticamente a cardinalidade dos dados intermédios, diminuindo consequentemente o consumo de memória e a latência de I/O.  

#figure(
  block(
    fill: luma(240),
    inset: 8pt,
    ```sql
SELECT interval, event, SUM(count) AS count
FROM (
    SELECT 
        date_bin('15 minutes', created_at, '2009-01-01') AS interval,
        'commit' AS event,
        COUNT(*) AS count
    FROM commit
    WHERE created_at BETWEEN '2020-01-01' AND '2020-06-01'
    GROUP BY 1

    UNION ALL

    SELECT 
        date_bin('15 minutes', opened_at, '2009-01-01') AS interval,
        'ticket_opened' AS event,
        COUNT(*) AS count
    FROM ticket
    WHERE opened_at BETWEEN '2020-01-01' AND '2020-06-01'
    GROUP BY 1
    ...
    e no final
    ...
    GROUP BY interval, event
    ORDER BY interval, event;
    ```
  ), caption: [Excerto da query otimizada] ,
)  <Q3-otimizada> 
#v(7pt)
=== Resultados finais
#figure(
  image("images/segundo.png"),
  caption: [Plano de Execução Q3 (versão otimizada).]
) <Q3-explainAnalyze2>
#v(7pt)

Na tabela abaixo estão definidos os tempos médios de execução (média obtida através de 10 execuções) da pesquisa, com as atualizações e alterações realizadas.
É importante referir também que, todos estes tempos, foram obtidos após ter sido realizada uma alteração tanto a nível de memória como na paralelização, através dos seguintes comandos:

#figure(
  block(
    fill: luma(240),
    inset: 8pt,
    ```text
SET work_mem = '10MB';
SET max_parallel_workers_per_gather = 6; 
    ```
  ),
) <Q3-5>
#v(7pt)
#align(center, 
  table(
    columns: (auto, auto, auto),
    align: (center, center),
    inset: 8pt,
    stroke: 0.5pt,

    [*intervalo de tempo*], [*bin*], [*tempo médio(s)*],
    [`2022-01-01 a 2025-01-01`], [`15 minutos`], [6.011 s],
    [`2022-01-01 a 2025-01-01`], [`60 minutos`], [5.552 s],
    [`2020-01-01 a 2020-06-01`], [`15 minutos`], [0.351 s],
  )
) <q3-optimized-times>
#v(7pt)
Podemos concluir assim que, a reformulação da query 3, juntamente com a criação de índices, resultaram numa maior eficiência.

=== Comparação com DuckDB

Os testes no DuckDB foram efetuados sobre a query original e estão representados na tabela abaixo.

#align(center, 
  table(
    columns: (auto, auto, auto),
    align: (center, center),
    inset: 8pt,
    stroke: 0.5pt,

    [*intervalo de tempo*], [*bin*], [*tempo médio(s)*],
    [`2022-01-01 a 2025-01-01`], [`15 minutos`], [1.428 s],
    [`2022-01-01 a 2025-01-01`], [`60 minutos`], [1.066 s],
    [`2020-01-01 a 2020-06-01`], [`15 minutos`], [0.109 s],
  )
) <q3-duckDB-times>
#v(7pt)
A análise dos tempos de execução, após a otimização da query, mostra uma redução significativa do custo no PostgreSQL. No entanto, mesmo com estes ganhos, os resultados obtidos com o DuckDB revelam-se consistentemente superiores, apresentando tempos ainda mais baixos, como 1.428 s e 1.066 s para os intervalos maiores, e apenas 0.109 s para o intervalo mais curto.

Apesar da melhoria substancial no PostgreSQL (redução de ~35s para ~6s), o DuckDB apresenta tempos consistentemente inferiores (cerca de 4x mais rápido no intervalo maior).

Isto não reflete uma falha na otimização do PostgreSQL, mas sim uma diferença arquitetural fundamental:
1. *DuckDB (OLAP/colunar):* o armazenamento orientado a colunas permite ler apenas os dados necessários (neste caso, as datas) e vetorizar as operações de agregação, o que é ideal para este tipo de _query_ analítica.
2. *PostgreSQL (OLTP/linha):* mesmo com índices, o motor orientado a linhas apresetna um _overhead_ natural ao reconstruir tuplas completas e gerir a concorrência (MVCC), o que limita a velocidade máxima em agregações massivas.

Em suma, embora a otimização aplicada tenha melhorado substancialmente o desempenho no PostgreSQL, a arquitetura interna do DuckDB continua mais adequada a este tipo de tarefa analítica, justificando os seus tempos de execução inferiores.

#pagebreak()
== Interrogação Analítica 4

A quarta interrogação analítica (Q4) visa gerar recomendações de repositórios para um dado utilizador. A lógica da consulta consiste em identificar "colegas de estrela" (utilizadores que deram estrela a repositórios em comum com o utilizador-alvo) e, subsequentemente, sugerir outros repositórios a que esses "colegas" também deram estrela.

A consulta exclui repositórios que o utilizador-alvo já marcou com estrela. O argumento da consulta é o `username`.

=== Desempenho _baseline_

A consulta original (_baseline_) utilizada para as medições é apresentada na figura abaixo. Esta versão utiliza a cláusula `NOT IN` para a lógica de exclusão.

#figure(
  block(
    fill:luma(240),
    inset:8pt,
    ```sql
    SELECT r.id, r.owner || '/' || r.name, r.description
    FROM users u
    JOIN star s1 ON u.username = s1.username
    JOIN star s2 ON s1.repository_id = s2.repository_id
        AND s1.username <> s2.username
    JOIN star s3 ON s3.username = s2.username
    JOIN repository r ON r.id = s3.repository_id
    WHERE u.username = 'christopherharmon25'
        AND s3.repository_id NOT IN (
            SELECT repository_id
            FROM star
            WHERE username = 'christopherharmon25'
        )
    GROUP BY 1, 2, 3
    ORDER BY count(*) DESC
    LIMIT 25;
    ```
  ),
  caption: [Código SQL da _query_ Q4 (versão original).]
) <Q4-base>
#v(7pt)
A versão original da _query_ apresentou tempos de execução muito elevados. A tabela resume os tempos médios obtidos através do script de medição automática (`arg_script.py`), executado cinco vezes por argumento.

#table(
  columns: (auto,auto),
  align: (center,center),
  inset:8pt,
  stroke:0.5pt,
  [*argumento (_username_)*], [*tempo médio (s)*],
  [`christopherharmon25`], [19.119 s],
  [`rdavila66`], [10.425 s],
  [`jenkinsbrandon52`], [9.097 s],
) <q4-baseline-times>

=== Análise do Plano de Execução (baseline)

Para diagnosticar a causa do baixo desempenho, gerou-se e analisou-se o plano de execução através do comando `EXPLAIN ANALYZE`. O plano (@fig:Q4-baseline) revelou que o desempenho era severamente degradado por múltiplas operações de `Parallel Seq Scan` (varredura sequencial) na tabela `star`, a maior tabela da base de dados.

#figure(
  image("images/Q4 (baseline).png"), 
  caption: [Plano de execução _baseline_ da _query_ 4.]
) <fig:Q4-baseline>
#v(7pt)
Identificaram-se os seguintes pontos de contenção:
1.  *Gargalo Principal:* um `Seq Scan` na tabela `star` (aliás _s3_), que demorava *6.5 segundos* a ler 45 milhões de linhas, apenas para alimentar um `Hash Join` cujo critério incluía a coluna `username`.
2.  *Gargalos Secundários:* múltiplos `Parallel Seq Scan` na tabela `star` (aliás _s1_ e no `SubPlan 1` do `NOT IN`) para filtrar pelo `username` do utilizador-alvo.

A origem principal desta ineficiência encontra-se na ausência de um índice adequado. O _schema_ define a chave primária da tabela `star` como (repository_id,username), solução eficiente para pesquisas por `repository_id`, mas totalmente ineficaz para filtros ou _joins_ cujo critério incide sobretudo sobre a coluna `username` (como ocorre em _s1_ e _s3_)

=== Indexação da Coluna `username`

Para lidar com os múltiplos `Seq Scans`, a primeira estratégia consistiu na criação de um índice B-tree na coluna `username` da tabela `star`.

#block(
  fill:luma(240),
  inset:8pt,
  ```sql
  CREATE INDEX idx_star_username ON star (username);
  ```
)

A introdução deste índice originou uma melhoria de desempenho significativa, reduzindo o tempo de execução para o utilizador `christopherharmon25` de 19.1s para 2.8s (aproximadamente 7× mais rápido). O novo plano de execução (@fig:Q4-index) confirmou que todos os `Seq Scan` ligados à coluna `username` passaram a ser substituídos por `Index Scan` de elevada rapidez.

#figure( image("images/Q4 (com índice).png"), 
  caption: [Plano de execução após a criação do índice `idx_star_username`.]
) <fig:Q4-index>
#v(7pt)
Apesar da melhoria, a análise deste novo plano revelou o gargalo seguinte: um `Nested Loop` executado 80 570 vezes. Além disso, o plano continuava a recorrer a um `Sort` para disco (_external merge_), sinalizando ineficiências na lógica de exclusão com `NOT IN`.

=== Reestruturação da Lógica de Exclusão (NOT EXISTS)

O segundo problema identificado resultava da utilização de `NOT IN`, uma construção que o _planner_ do _PostgreSQL_ raramente trata de forma eficiente, resultando num Hashed SubPlan.

A lógica da consulta passou a recorrer a `NOT EXISTS`, uma construção que o _PostgreSQL_ gere com maior eficiência. Esta alteração, combinada com o índice já existente, reduziu o tempo de execução de 2.8s para 1.92s.

#block(
  fill:luma(240),
  inset:8pt,
  ```sql
  SELECT r.id, r.owner || '/' || r.name, r.description
  FROM users u
  JOIN star s1 ON u.username = s1.username
  JOIN star s2 ON s1.repository_id = s2.repository_id
      AND s1.username <> s2.username
  JOIN star s3 ON s3.username = s2.username
  JOIN repository r ON r.id = s3.repository_id
  WHERE u.username = 'christopherharmon25'
  AND NOT EXISTS (
      SELECT 1
      FROM star s_exclude
      WHERE s_exclude.repository_id = s3.repository_id
      AND s_exclude.username = 'christopherharmon25'
  )
  GROUP BY 1, 2, 3
  ORDER BY count(*) DESC
  LIMIT 25;
  ```
)

O plano de execução final (@fig:Q4-final) demonstra o sucesso desta abordagem. O _SubPlan_ de `NOT IN` encontra-se agora substituído por um `Merge Join (Anti)` altamente eficiente, que realiza a exclusão em apenas 42 ms.

#figure( image("images/Q4 (final).png"), 
  caption: [Plano de execução final com NOT EXISTS.] 
) <fig:Q4-final>
#v(7pt)
O gargalo remanescente, um `Nested Loop` que demora 1.28s, representa agora o custo computacional real e inevitável de processar os 80 570 “colegas de estrela” do utilizador `christopherharmon25`.

=== Resultados Finais

A tabela resume o impacto das alterações aplicadas, comparando os tempos médios da versão _baseline_ com a versão final (índice + NOT EXISTS).

#table( columns: (auto, auto, auto), 
  align: (center, center, center), 
  inset: 8pt, 
  stroke: 0.5pt, 
  [*argumento (_username_)*], [*tempo base (s)*], [*tempo final (s)*], 
  [christopherharmon25], [19.119 s], [1.920 s], 
  [rdavila66], [10.425 s], [0.217 s], 
  [jenkinsbrandon52], [9.097 s], [0.012 s] 
) <Q4-results>

Em conclusão, a reformulação da _query_ 4 revela-se claramente eficaz, demonstrando como uma abordagem em duas fases (primeiro resolvendo o gargalo de I/O com um índice estratégico e depois ajustando a lógica da consulta com NOT EXISTS) reduziu o tempo de execução em cerca de 90% (aproximadamente 10× mais rápido) para o caso de teste principal.

=== Comparação com DuckDB

Os testes no `DuckDB` foram executados diretamente sobre os dados originais, medindo o tempo de resposta wall-clock para garantir consistência nas métricas. A @tab:comparação apresenta os resultados obtidos para a query 4.

#figure(
  table(
    columns: (auto, auto, auto, auto),
    inset: 8pt, 
    stroke: 0.5pt,
    table.header(
      [*argumento*],
      [*PostgreSQL* \ (optimizado)],
      [*DuckDB* \ (sem optimização)],
      [*diferença*]
    ),
    "christopherharmon25", "1.920 s", "1.395 s", text(fill: red)[DuckDB -27%],
    "rdavila66", "0.217 s", "1.344 s", text(fill: green)[postgreSQL -84%],
    "jenkinsbrandon52", "0.012 s", "1.137 s", text(fill: green)[postgreSQL -98%],
  ),
  caption: [Comparação de desempenho: PostgreSQL optimizado vs. DuckDB sem optimização.]
) <tab:comparação>
#v(7pt)
//https://db.cs.uni-tuebingen.de/explain/plan/c7df3e67eg2fe8dc

A análise dos resultados evidencia duas realidades distintas:

1.  *Cargas pesadas (agregação):* no cenário mais exigente (`christopherharmon25`), o DuckDB superou o PostgreSQL (1.4s vs 1.9s). A análise do plano de execução revelou que o DuckDB recorreu a força bruta, varrendo sequencialmente 160 milhões de registos na tabela `star`. A sua vantagem reside na arquitetura colunar, que lê apenas os dados estritamente necessários do disco.

2.  *Acessos pontuais (latência):* nos cenários de alta seletividade (rdavila66 e jenkinsbrandon52), o PostgreSQL apresenta tempos consideravelmente inferiores (0.01 s vs 1.14 s). O índice B-Tree criado permite validar rapidamente a existência de registos, com complexidade $O(log N)$. O DuckDB, sem suporte a índices, precisa de varrer a tabela para confirmar presença ou ausência de dados, incorrendo sempre num custo fixo inicial.

Em síntese, a arquitetura colunar do DuckDB proporciona um desempenho base muito competitivo em cargas analíticas de grande volume, enquanto o PostgreSQL (através de índices e do `NOT EXISTS`) garante vantagens claras em consultas que exigem latências reduzidas e acessos altamente seletivos.

= Carga Transacional

A componente transacional do trabalho prático simula um cenário de utilização intensiva de uma plataforma de gestão de repositórios. O objetivo desta fase consistiu na maximização do débito (_throughput_) e minimização da latência das operações (_response time_).

No cenário inicial, sem quaisquer estruturas de optimização, o sistema registou um desempenho de aproximadamente *78 transações por segundo (txn/s)*, com um *tempo de resposta superior a 200 ms*. A análise dos tempos de execução revelou que a latência era dominada por três operações de leitura, que consumiam excessivos recursos de CPU e I/O devido a varrimentos completos das tabelas e ordenações em memória.

== Optimização através de Índices

A estratégia de indexação focou-se nas colunas utilizadas em cláusulas de filtragem (`WHERE`), junção (`JOIN`) e ordenação (`ORDER BY`) das interrogações críticas. Após análise dos planos de execução gerados pelo PostgreSQL através do comando `EXPLAIN ANALYZE`, identificaram-se os seguintes gargalos:

- *pesquisa textual (`SearchRepositories`):* a operação recorria a um _scan_ sequencial para calcular vetores de texto em tempo de execução. A implementação de um índice invertido (GIN) na coluna `description` da tabela `repository` permitiu substituir o varrimento por uma pesquisa indexada eficiente:

```sql
CREATE INDEX idx_repository_description_gin 
ON repository USING GIN(to_tsvector('english',description));
```

#figure(
  grid(
    columns: (1fr,1fr),
    gutter:1em,
    align(center)[
      #image("images/SR-a.png", width:100%)
    ],
    align(center)[
      #image("images/SR-d.png", width:100%)
    ]
  ),
  caption: [Comparação do plano de execução da query `SearchRepositories` antes e depois da criação do índice GIN na coluna `description`.]
) <fig:SR-idx>

 - *perfil de utilizador (`GetUserInfo`):* esta interrogação filtrava repositórios por proprietário e ordenava-os por data. A criação de um índice composto permitiu satisfazer ambos os requisitos simultaneamente, eliminando a necessidade de uma etapa de ordenação explícita (_Sort_):

```sql
CREATE INDEX idx_repository_owner_pushed_at 
ON repository(owner,pushed_at DESC);
```

#figure(
  grid(
    columns: (1fr, 1fr),
    gutter:1em,
    align(center)[
      #image("images/GUI-a.png", width:100%)
    ],
    align(center)[
      #image("images/GUI-d.png", width:100%)
    ]
  ),
  caption: [Impacto do índice composto `idx_repository_owner_pushed_at` na query `GetUserInfo`, eliminando a operação de ordenação (Sort).]
) <fig:GUI-idx>
#v(7pt)
- *listagem por linguagem (`GetRepositoriesByLanguage`):* identificou-se que a junção com a tabela `repository_languages` era o principal gargalo. A criação de um índice na chave estrangeira `language_id` otimizou significativamente a operação de junção:

```sql
CREATE INDEX idx_repository_languages_language_id 
ON repository_languages(language_id);
```

#figure(
  grid(
    columns: (1fr, 1fr),
    gutter:1em,
    align(center)[
      #image("images/GRL-a.png", width:100%)
    ],
    align(center)[
      #image("images/GRL-d.png", width:100%)
    ]
  ),
  caption: [Optimização da junção na query `GetRepositoriesByLanguage` através da indexação da chave estrangeira `language_id`.]
) <fig:GRL-idx>
#v(7pt)
Durante a fase de testes, explorou-se a criação de um índice adicional na coluna `created_at` da tabela `repository` com o intuito de otimizar a ordenação temporal. Contudo, observou-se uma degradação de desempenho. A análise do plano de execução revelou que o optimizador do PostgreSQL, ao utilizar este índice, optava por um _Index Scan_ seguido de _Nested Loops_. Para linguagens com baixa cardinalidade (poucos repositórios), esta estratégia obrigava o motor de base de dados a ler e descartar milhares de registos aleatórios até encontrar o número suficiente de correspondências, revelando-se menos eficiente do que a ordenação em memória (_Sort_) dos resultados filtrados. Consequentemente, optou-se por não incluir este índice na solução final.

A aplicação dos índices selecionados resultou num aumento de débito superior a 10 vezes em relação à configuração base, conforme demonstrado na @tbl:res-idx.

#figure(
  table(
    columns: (auto, auto, auto, auto),
    inset: 10pt,
    align: horizon,
    table.header(
      [*métrica*], [*sem índices*], [*com índices*], [*melhoria*],
    ),
    [throughput (txn/s)], [77.81], [812.07], [+943.6%],
    [SearchRepositories (ms)], [623.71], [31.57], [−94.9%],
    [GetRepositoriesByLanguage (ms)], [1914.81], [291.22], [−84.8%],
    [GetUserInfo (ms)], [1447.47], [1.62], [−99.9%],
  ),
  caption: [Comparação de _performance_: baseline vs. versão com índices.],
) <tbl:res-idx>

== Optimização de Parâmetros de Configuração

Após a estabilização do esquema físico através da criação de índices, procedeu-se à otimização dos parâmetros de configuração do PostgreSQL. A estratégia de otimização seguiu uma abordagem hierárquica, começando pela alocação de memória (o recurso mais crítico), passando pelo paralelismo de CPU, e terminando no ajuste fino das garantias de durabilidade (I/O).

=== shared_buffers

O parâmetro `shared_buffers` é responsável por estipular o volume de memória que o servidor reserva para o armazenamento em _cache_ de blocos de dados. Um valor adequado reduz a necessidade de leituras frequentes ao disco, mantendo os dados mais acedidos em memória. Verificando a configuração inicial do sistema, obteve-se:

```
git=# SHOW shared_buffers;
 shared_buffers 
----------------
 128MB
(1 row)
```

Executando o comando `free -m` na máquina virtual, foi possível verificar a disponibilidade de recursos:

#figure(
  table(
    columns: (auto, auto, auto,auto,auto),
    inset: 10pt,
    align: horizon,
    table.header(
      [*total (MB)*], [*used (MB)*], [*free (MB)*], [*shared (MB)*], [*buff/cache (MB)*]
    ),
    [15980], [708], [1864], [2113], [13407],
  ),
  caption: [Informação de memória disponível no sistema.],
) <tbl:memory_info>
#v(7pt)
Com aproximadamente 15GB de memória RAM disponível, o valor por defeito de 128MB é manifestamente insuficiente. A documentação do PostgreSQL recomenda valores entre 20% e 25% da memória total do sistema para este parâmetro. Realizou-se uma análise de sensibilidade testando valores progressivos (1GB, 2GB, 4GB e 8GB) para determinar o ponto de equilíbrio ideal.

A @tbl:shared_buffers apresenta os resultados obtidos para cada configuração testada, enquanto a @fig:sb_chart ilustra graficamente a evolução do desempenho.

#figure(
  table(
    columns: (auto,auto,auto,auto),
    inset: 10pt,
    align: horizon,
    table.header(
      [*configuração*], [*throughput (txn/s)*], [*latência média (ms)*], [*variação*],
    ),
    [128 MB (base)], [812.07], [19.57], [—],
    [1 GB], [956.63], [16.61], [+17.8%],
    [2 GB], [980.40], [16.37], [+2.5%],
    [4 GB], [1085.88], [14.72], [+10.7%],
    [8 GB], [1001.40], [15.97], [−7.8%],
  ),
  caption: [Impacto da alocação de `shared_buffers` no desempenho transacional.],
) <tbl:shared_buffers>

#figure(
  image("images/gráfico (shared buffers).png", width: 100%),
  caption: [Evolução do _throughput_ em função do `shared_buffers`.],
) <fig:sb_chart>
#v(7pt)
Observou-se um crescimento consistente do desempenho até à configuração de 4GB, onde se atingiu o pico de 1085 txn/s e a latência mínima de 14.72 ms. Este valor corresponde a aproximadamente 25% da memória total do sistema, alinhando-se com as recomendações gerais da documentação do PostgreSQL.

Contudo, ao aumentar a alocação para 8GB (50% da RAM), registou-se uma regressão de desempenho, com o débito a cair para 1001 txn/s e a latência a aumentar para 15.97 ms. Este fenómeno justifica-se pelo mecanismo de _dupla cache_ ("double buffering"). O PostgreSQL depende não só do seu `shared_buffers`, mas também da _cache_ de sistema de ficheiros do sistema operativo (OS Cache) para gerir escritas e leituras que excedem o _buffer_ interno. Ao alocar uma porção excessiva de RAM exclusivamente ao PostgreSQL (8GB), reduziu-se a memória disponível para o sistema operativo gerir ligações, processos concorrentes e a sua própria _cache_ de ficheiros, resultando numa contenção de recursos que prejudicou o desempenho global.

Conclui-se, portanto, que *4GB* é o valor ideal para este cenário, maximizando a utilização de _cache_ interna sem comprometer o equilíbrio de recursos do sistema.

=== work_mem


O parâmetro `work_mem` define a quantidade máxima de memória que *cada* operação interna de ordenação (_sort_) ou _hash_ pode utilizar antes de recorrer a ficheiros temporários em disco. Este parâmetro é particularmente relevante em _joins_ (ex.: `Hash Join`), agregações, operações de ordenação e também em alguns cenários com `Bitmap Heap Scan`, onde estruturas intermédias podem tornar-se mais pesadas e levar a trabalho adicional.

Verificando a configuração inicial:

#quote(block: true)[
  `git=# SHOW work_mem;` \
  `4MB`
]

A @tbl:config-base apresenta os resultados obtidos com o `EXPLAIN ANALYZE` para a configuração-base de 4MB.

#figure(
  table(
    columns: (auto,auto,auto,auto),
    inset: 10pt,
    align: horizon,

    table.header(
      [*query*],
      [*operação principal*],
      [*planning (ms)*],
      [*execution (ms)*],
    ),

    [CreateRepository], [_Insert_], [0.097], [1.126],
    [AddStar], [_Insert_], [0.013], [0.095],
    [GetRepositoryPage], [_Index Scan_], [1.273], [0.389],
    [GetReposbyLanguage], [_Nested Loop_], [0.196], [5.829],
    [GetUserProfile], [_Index Scan_], [0.128], [0.023],
    [GetUserRepos], [_Nested Loop_], [0.081], [0.065],
    [GetTicketPage], [_Index Scan_], [0.151], [0.013],
    [SearchRepository], [_Bitmap Heap Scan_], [0.070], [11.373],
  ),
  caption: [Resultados do EXPLAIN ANALYZE com work_mem = 4MB.],
) <tbl:config-base>
#v(7pt)
Analisando os resultados da @tbl:config-base, retiram-se as seguintes conclusões:

- *pesquisa textual*: a query `SearchRepository` destaca-se agora como a mais lenta (\~11.4ms), utilizando um `Bitmap Heap Scan`. Com apenas 4MB, a gestão dos *bitmaps* em memória para os resultados da pesquisa textual (`to_tsvector`) pode ser um fator limitante, tornando-a a principal candidata a optimização.
- *_joins_ e agregações*: a query `GetReposbyLanguage` (\~ 5.8ms) utiliza `Nested Loop`. Este comportamento sugere que o otimizador não encontrou benefício suficiente (ou condições) para optar por estratégias baseadas em _hash_ (ex.: `Hash Join`), ou que os custos associados às alternativas não compensam no contexto atual.
- *inserções*: `CreateRepository` (\~ 1.1ms) mostra-se eficiente. Como esperado, `work_mem` tende a ter impacto reduzido em escritas simples, cujo custo é normalmente dominado por WAL, _locks_ e I/O.
- *leituras rápidas*: queries como `GetTicketPage` e `GetUserProfile` apresentam tempos vestigiais (< 0.1ms), confirmando que os índices e o acesso pontual (`Index Scan`) estão a funcionar corretamente.

Com base nesta análise, aumentou-se o `work_mem` para *16MB* e *32MB*, focando a atenção na evolução das queries `SearchRepository` e `GetReposbyLanguage`.

#figure(
  image("images/gráfico (work memory).png", width: 100%),
  caption: [Impacto do aumento de work_mem (4MB, 16MB e 32MB) no tempo de execução das queries.],
) <fig:work-mem>
#v(7pt)
Analisando os resultados globais apresentados na @fig:work-mem, observam-se os seguintes comportamentos:

- *SearchRepository*: esta query apresenta a melhoria mais significativa, com uma redução de \~22% no tempo de execução ao aumentar de 4MB (\~11.3ms) para 32MB (\~8.8ms). O aumento para 16MB já proporciona ganhos notáveis (\~10.7ms), indicando que operações com `Bitmap Heap Scan` e filtragem textual beneficiam de maior disponibilidade de memória para processamento intermédio.

- *GetReposbyLanguage*: observa-se uma melhoria modesta mas consistente, com tempos a reduzirem de \~5.8ms (4MB) para \~5.3ms (32MB). Embora o optimizador continue a utilizar `Nested Loop` em vez de `Hash Join`, a memória adicional permite uma gestão mais eficiente das operações intermediárias e do _buffer_ de dados durante a execução dos _joins_.

- *operações sem impacto significativo*: `Add Star`, `Get Repository Page`, `Get Ticket Page`, `Get User Profile` e `Get User Repos` mantêm tempos praticamente constantes independentemente do `work_mem`. Isto confirma que estas operações, dominadas por `Index Scan` ou inserções simples, não são limitadas por este parâmetro.

De forma agregada, os testes demonstram que o aumento de `work_mem` melhora sobretudo operações específicas:

1. *pesquisas textuais* beneficiam significativamente, com reduções até 22% no tempo de execução.
2. *_joins_ e agregações* apresentam melhorias moderadas (5%-10%), sugerindo que outros fatores (cardinalidade, seletividade, desenho de índices e distribuição de dados) podem ser determinantes para ganhos adicionais.
3. *ponto de retornos decrescentes*: a diferença entre 16MB e 32MB é menor do que entre 4MB e 16MB, indicando que aumentos adicionais tendem a produzir ganhos marginais.

Assim, *recomenda-se a configuração `work_mem = 16MB`* como um compromisso equilibrado entre _performance_ e a utilização de memória. Este valor permite capturar a maior parte dos ganhos observados (em particular na interrogação `SearchRepository`) sem introduzir o risco acrescido de pressão sobre a memória associado a 32MB, sendo, por isso, mais adequado a ambientes com múltiplas interrogações concorrentes.

=== effective_cache_size

O parâmetro `effective_cache_size` fornece ao _planner_ do PostgreSQL uma estimativa da quantidade de dados que pode estar em cache durante a execução de queries. Este valor *não* reserva memória real, influenciando apenas o modelo de custos do optimizador. Em termos práticos, `effective_cache_size` representa uma estimativa da cache efetivamente disponível para leituras, tipicamente englobando o `shared_buffers` do PostgreSQL e a _page cache_ do sistema operativo. Valores mais altos tendem a reduzir o custo estimado de acessos aleatórios, favorecendo a utilização de índices em detrimento de varrimentos sequenciais (_sequential scans_) quando existe ambiguidade na escolha do plano.

Dado que a máquina utilizada dispõe de 16GB de RAM, e tendo identificado a transação `SearchRepositories` (pesquisa de texto) como uma das mais custosas no _benchmark_ transacional, focámos a análise no impacto deste parâmetro no tempo de execução desta _query_ específica.

Foram testados três cenários de configuração para o `effective_cache_size`: *4GB*, *8GB* e *12GB*. Para cada configuração, executou-se a _query_ de pesquisa textual utilizando `EXPLAIN (ANALYZE,BUFFERS)` para medir o tempo de execução e analisar o plano escolhido pelo optimizador.

A _query_ analisada foi:

```sql
SELECT id, name, owner, description
FROM repository
WHERE to_tsvector('english',description) @@ to_tsquery('english','java')
LIMIT 100;
```
A @tab:cache_results apresenta os tempos médios obtidos nas três configurações (a variação observada é pequena e compatível com ruído normal do sistema, já que o plano se manteve inalterado):

#figure(
  table(
    columns: (1fr, 1fr),
    inset: 10pt,
    align: horizon,
    [*configuração*], [*tempo de execução (ms)*],
    [4 GB], [13.964],
    [8 GB], [13.506],
    [12 GB], [13.481],
  ),
  caption: [Tempos de execução da query `SearchRepositories` para diferentes tamanhos de cache.],
) <tab:cache_results>
#v(7pt)
A análise do `EXPLAIN` revelou que, em todos os cenários, o PostgreSQL escolheu o mesmo tipo de estratégia: um `Bitmap Index Scan` sobre o índice GIN (`idx_repository_description_gin`), seguido de `Bitmap Heap Scan` para obter os tuplos no _heap_. Ou seja, variar `effective_cache_size` não foi suficiente para alterar a decisão do optimizador (índice vs _seq scan_), mantendo-se o mesmo plano lógico.

Além disso, a análise dos buffers revelou que a maior parte dos blocos necessários foi servida diretamente a partir da cache interna do PostgreSQL (ou seja, os `shared_buffers`), conforme evidenciado pelos contadores de _shared hit_ no output do EXPLAIN.

```text
Buffers: shared hit=408
...
Heap Blocks: exact=75
Buffers: shared hit=333
```


Ao contrário do que seria expectável em cenários onde o índice não cabe em memória, a alteração do `effective_cache_size` *não teve impacto significativo* no desempenho desta interrogação, com os tempos a estabilizarem em torno dos 13.5 ms (a ligeira variação observada insere-se na margem de ruído normal do sistema).

Este resultado explica-se por dois fatores principais:

1. *plano já “dominante” com GIN*: para esta pesquisa (`to_tsvector` @@ `to_tsquery`), o índice GIN apresenta uma seletividade suficientemente forte para que o _planner_ prefira sempre a estratégia baseada em índice, mesmo com uma estimativa conservadora de cache (4GB). Aumentar para 12GB apenas reforça uma decisão que já era claramente a mais barata no modelo de estimativa de custos.

2.  *dados em `Shared Buffers`:* a predominância de shared hits indica que tanto o índice como os blocos relevantes do heap já se encontravam nos `shared_buffers`. Como não houve alteração no plano de execução e a maioria dos acessos não implicou leituras físicas, o parâmetro `effective_cache_size` teve pouca influência na latência observada para esta operação.

Conclui-se que, para o volume de dados atual e para este perfil de pesquisa textual, variar o valor de `effective_cache_size` não altera o plano nem produz ganhos relevantes. Assim, a configuração base de memória já é suficiente para garantir a escolha do plano de execução ideal.

=== Paralelismo

O PostgreSQL suporta execução paralela de queries, permitindo acelerar operações de leitura intensiva (por exemplo, `Parallel Seq Scan`, alguns tipos de agregação e junções com volumes elevados). Este mecanismo cria _background workers_ adicionais, coordenados por um processo-líder, o que pode reduzir o tempo de execução quando o custo de processamento compensa o overhead de coordenação e sincronização. Numa máquina com 8 vCPUs, o objetivo é encontrar um ponto de equilíbrio entre paralelismo intra-query e o número total de workers ativos no servidor, evitando saturação de CPU e degradação por contenção.

Para ajustar o paralelismo, focámo-nos em dois parâmetros:

*_max_parallel_workers_per_gather_*: número máximo de _workers_ que podem ser utilizados por cada nó `Gather`/`Gather Merge` de um plano. Na prática, este parâmetro define o teto do paralelismo *por query*, embora uma query possa ter mais do que um nó `Gather`.

*_max_parallel_workers_*: número máximo global de _parallel workers_ que podem estar ativos simultaneamente no servidor. Este valor limita o paralelismo total do sistema sob concorrência, independentemente do valor configurado por query.

Antes de aplicar alterações globais, avaliou-se o impacto do paralelismo numa interrogação de leitura intensiva, `GetRepositoriesByLanguage`, que envolve junções e ordenação. Variou-se o número máximo de workers por query e mediu-se o tempo de execução via `EXPLAIN ANALYZE`:

#figure(
  table(
    columns: (auto,auto,auto),
    inset: 10pt,
    align: horizon,
    table.header(
      [*workers (per_gather)*],
      [*tempo de execução (ms)*],
      [*melhoria (%)*],
    ),
    [2 (default)], [48.76], [-],
    [3], [38.06], [\~ 22%],
    [4], [37.62], [\~ 23%],
    [5], [38.15], [\~ 22%],
  ),
  caption: [Impacto do `max_parallel_workers_per_gather` no tempo de execução da query GetRepositoriesByLanguage.]
) <tbl:parallel-per-gather>
#v(7pt)
Observa-se um ganho substancial ao aumentar de 2 para 3 workers, o que indica que existia trabalho paralelizável suficiente para compensar o custo de coordenação. A partir de 3 workers, verifica-se a lei dos rendimentos decrescentes: a diferença entre 3 e 4 é marginal e pode situar-se perto do ruído experimental, enquanto 5 workers já não traz benefício e até piora ligeiramente. Assim, selecionou-se `max_parallel_workers_per_gather = 4` como valor de referência, por representar o melhor valor observado sem inflacionar excessivamente o paralelismo por query.

De seguida, realizaram-se testes sob carga transacional com várias combinações de `max_parallel_workers_per_gather` e `max_parallel_workers`, medindo-se throughput e tempo médio de resposta. O objetivo foi avaliar não apenas o desempenho de uma query isolada, mas o comportamento do sistema quando múltiplas sessões competem por CPU e por workers paralelos.

#figure(
  table(
    columns: (auto,auto,auto),
    inset: 10pt,
    align: horizon,
    table.header(
      [*configuração \ (per_gather,global)*],
      [*throughput (txn/s)*],
      [*response time (ms)*],
    ),
    [4,8], [1189.06], [13.47],
    [4,16], [1163.70], [13.80],
    [4,32], [1128.23], [14.20],
    [2,32], [1100.21], [14.51],
  ),
  caption: [Impacto de `max_parallel_workers_per_gather` e `max_parallel_workers` no desempenho transacional.]
) <tbl:parallel-global>
#v(7pt)
A análise da @tbl:parallel-global evidencia dois padrões relevantes. Primeiro, mantendo o limite global de workers elevado (32), o aumento do paralelismo por query de 2 para 4 workers traduz-se num aumento do throughput e numa redução da latência, indicando que as interrogações mais exigentes do benchmark beneficiam de um maior grau de paralelismo quando existem recursos disponíveis. Segundo, o melhor desempenho absoluto é observado na configuração (4,8), que supera configurações com limites globais superiores (16 e 32), apesar de estas permitirem, em teoria, um maior número de workers.

Este comportamento pode ser explicado por dois efeitos típicos em cenários de carga elevada em máquinas com CPU limitada. Por um lado, limites globais excessivamente elevados intensificam a competição por CPU, aumentando o overhead de escalonamento e reduzindo a previsibilidade do tempo de resposta. Por outro, quando múltiplas sessões tentam explorar paralelismo em simultâneo, o sistema pode acabar por atribuir menos workers por interrogação do que o configurado, devido à indisponibilidade de workers livres, desperdiçando assim parte do custo de planeamento e coordenação sem alcançar o ganho de desempenho paralelo esperado.

Com base nestes resultados, determinou-se como configuração recomendada para este ambiente `max_parallel_workers_per_gather = 4` e `max_parallel_workers = 8`. Esta combinação maximiza o benefício em queries complexas sem exceder a capacidade de processamento das 8 vCPUs, produzindo simultaneamente o maior throughput e a menor latência média observados nos testes.


=== fsync

O parâmetro _fsync_ controla se o PostgreSQL força a escrita efetiva de WAL e ficheiros de dados no armazenamento persistente, garantindo que uma transação só é considerada concluída quando a informação necessária para a sua durabilidade foi efetivamente persistida. Com `fsync = off`, o servidor deixa de emitir operações de sincronização para disco, delegando essa responsabilidade no _page cache_ do sistema operativo, o que elimina garantias de durabilidade e pode conduzir a corrupção de dados após falhas de energia, _crashes_ do kernel ou reinícios inesperados.

Nesta secção avaliou-se o impacto desta alteração, comparando o desempenho com a configuração-base optimizada anteriormente (`max_parallel_workers_per_gather = 4` e `max_parallel_workers = 8`), mantendo o restante ambiente e carga constantes.

#figure(
  table(
    columns: (auto,auto,auto,auto),
    inset: 10pt,
    align: horizon,
    table.header(
      [*configuração*],
      [*throughput (txn/s)*],
      [*response time \ (ms)*],
      [*variação \ (throughput)*],
    ),
    table.hline(),
    [fsync ON (base)], [1189.06], [13.47], [-],
    [fsync OFF], [1138.41], [13.63], [-4.3%],
    table.hline(),
  ),
  caption: [Impacto da desativação do _fsync_ no desempenho transacional.]
) <tbl:fsync-global>

Para compreender este resultado, analisaram-se também os tempos médios por query:

#figure(
  table(
    columns: (auto,auto,auto,auto),
    inset: 10pt,
    align: horizon,
    table.header(
      [*query*],
      [*tempo base (ms)*],
      [*tempo fsync="off" (ms)*],
      [*variação*],
    ),
    table.hline(),
    [CreateRepository], [1.802], [0.709], [-60.7%],
    [StarRepository], [2.092], [1.112], [-46.8%],
    [CreateCommit], [2.858], [1.687], [-41.0%],
    [CreateTicket], [1.921], [0.805], [-58.1%],
    [CloseTicket], [2.209], [1.067], [-51.7%],
    [GetRepositoryInfo], [7.753], [7.078], [-8.7%],
    [GetRepositoriesByLanguage], [174.007], [191.181], [+9.9%],
    [GetUserInfo], [1.357], [1.467], [+8.1%],
    [GetTicketInfo], [0.875], [0.921], [+5.3%],
    [SearchRepositories], [34.969], [37.623], [+7.6%],
    table.hline(),
  ),
  caption: [Tempo de resposta por query com fsync=off.]
) <tbl:fsync-per-query>
#v(7pt)
Os resultados mostram um comportamento assimétrico. As operações de escrita obtêm ganhos expressivos (por exemplo, `CreateRepository` e `CreateTicket`), o que é consistente com a remoção da latência associada a sincronização para armazenamento persistente. No entanto, várias operações de leitura (e, em particular, leituras pesadas como `GetRepositoriesByLanguage` e `SearchRepositories`) degradam, o que explica a redução do throughput global observada na @tbl:fsync-global.

Uma explicação plausível para esta degradação é o efeito de interferência entre escrita e leitura no subsistema de I/O e na gestão de memória do sistema operativo. Com `fsync = off`, o volume de dados “sujos” (_dirty pages_) tende a acumular no _page cache_ e é posteriormente descarregado para disco por mecanismos de _writeback_ do kernel em rajadas, podendo criar períodos de saturação de I/O e maior latência para leituras concorrentes. Em paralelo, a pressão de memória causada por mais páginas sujas pode aumentar a expulsão de dados úteis da cache, elevando a probabilidade de leituras irem ao disco e agravando ainda mais as queries de leitura pesada.

Conclui-se que `fsync = off` não só remove uma garantia crítica de durabilidade como também se revelou contraproducente em desempenho agregado (redução de 4.3% no throughput). Assim, *recomenda-se manter `fsync = on`*.


=== synchronous_commit

O parâmetro synchronous_commit define o grau de sincronização exigido no processamento do WAL (Write-Ahead Log) antes de o servidor confirmar o sucesso de uma transação ao cliente. No modo normal (valor por omissão, on), a confirmação do commit só é devolvida após o flush do WAL para armazenamento persistente. Quando configurado como synchronous_commit = off, esta espera é eliminada, permitindo que o servidor reporte o sucesso da transação assim que esta fica logicamente concluída.

Esta configuração introduz um risco limitado de perda das transações mais recentes em caso de crash, correspondente à janela temporal entre a confirmação ao cliente e a persistência efetiva do WAL. No entanto, não compromete a consistência nem a integridade da base de dados: no pior cenário, o estado recuperado após falha é semanticamente equivalente ao de essas transações nunca terem sido confirmadas, isto é, terem sido abortadas.

A alteração foi testada sobre a configuração-base optimizada (4 workers por query e 8 workers globais), mantendo a carga e o ambiente constantes.

#figure(
  table(
    columns: (auto,auto,auto,auto),
    inset: 10pt,
    align: horizon,
    table.header(
      [*configuração*],
      [*throughput (txn/s)*],
      [*response time (ms)*],
      [*variação*],
    ),
    [sync_commit ON (base)], [1189.06], [13.47], [-],
    [sync_commit OFF], [1075.88], [14.77], [-9.5%],
  ),
  caption: [Impacto do synchronous_commit no desempenho transacional.]
) <tbl:sync-global>
#v(7pt)
#figure(
  table(
    columns: (auto,auto,auto,auto),
    inset: 10pt,
    align: horizon,
    table.header(
      [*query*],
      [*tempo base (ms)*],
      [*tempo sync_commit=off (ms)*],
      [*variação*],
    ),
    [CreateRepository], [1.802], [0.784], [-56.5%],
    [StarRepository], [2.092], [1.095], [-47.7%],
    [CreateCommit], [2.858], [1.862], [-34.8%],
    [CreateTicket], [1.921], [0.884], [-54.0%],
    [CloseTicket], [2.209], [1.189], [-46.2%],
    [GetRepositoryInfo], [7.753], [7.400], [-4.6%],
    [GetRepositoriesByLanguage], [174.007], [198.557], [+14.1%],
    [GetUserInfo], [1.357], [1.567], [+15.5%],
    [GetTicketInfo], [0.875], [1.073], [+22.6%],
    [SearchRepositories], [34.969], [49.559], [+41.7%],
  ),
  caption: [Tempo de resposta por query com synchronous_commit=off.]
) <tbl:sync-per-query>
#v(7pt)
A desativação do _synchronous_commit_ produziu um _trade-off_ claro entre latência de escrita e desempenho global. As operações de escrita beneficiaram significativamente (por exemplo, `CreateTicket` reduziu de 1.92 ms para 0.88 ms e `CreateCommit` de 2.86 ms para 1.86 ms), o que é consistente com commits assíncronos que deixam de bloquear à espera do _flush_ do WAL.

Apesar disso, o throughput global caiu 9.5% (@tbl:sync-global), acompanhado por um aumento relevante no tempo de resposta de queries de leitura pesada (@tbl:sync-per-query), com destaque para `GetRepositoriesByLanguage` (+14%) e `SearchRepositories` (+42%). Uma interpretação plausível é que, ao deslocar parte do trabalho de persistência para flushing assíncrono, o sistema fica mais sujeito a interferência entre escrita e leitura (contenção de CPU/I/O e maior variabilidade), o que penaliza desproporcionalmente as queries mais longas e acaba por reduzir o débito agregado.

Embora `synchronous_commit = off` reduza a latência de escritas isoladas, neste _workload_ degradou o desempenho global e introduz um risco de perda das transações mais recentes em caso de _crash_. Por isso, *recomenda-se manter `synchronous_commit = on`* como configuração default.

= Conclusão
O presente trabalho evidenciou a relevância de uma abordagem estruturada à otimização de bases de dados relacionais, cobrindo cargas analíticas e transacionais. Com base na análise de planos de execução, foram identificados gargalos e aplicadas estratégias de indexação, reestruturação de queries e ajustes de configuração. Os resultados apontam para ganhos consistentes de desempenho, reforçando o impacto de decisões informadas no desenho e na configuração do sistema.
