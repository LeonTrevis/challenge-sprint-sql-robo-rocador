# Robô de Roçagem de Grama — SQL Aplicado ao Challenge

## Contexto do Projeto

Este projeto parte do Challenge de inovação em estradas, onde o objetivo é **automatizar a roçagem de grama nos acostamentos das estradas**, com uma solução barata e robusta. O grupo desenvolveu um robô terrestre equipado com sensores de distância (ultrassom), vibração e giroscópio (pitch), planejado para operar em terreno irregular com transições entre níveis.

Para a Sprint 3, os dados coletados pelos sensores foram organizados em um banco de dados PostgreSQL e consultados via SQL para responder a perguntas relevantes à empresa e à operação do robô.

> Nota: a câmera centralizada para navegação autônoma está prevista para implementação futura, mas não está incluída nesta entrega.

---

## Estrutura do Banco de Dados

### Tabela `sessoes_rocagem`

Registra cada sessão de operação do robô em um trecho do acostamento.

| Coluna              | Tipo         | Descrição                            |
|---------------------|--------------|--------------------------------------|
| `id`                | SERIAL PK    | Identificador único da sessão        |
| `nome`              | VARCHAR(100) | Nome/descrição do trecho             |
| `data_inicio`       | TIMESTAMP    | Início da sessão                     |
| `data_fim`          | TIMESTAMP    | Fim da sessão                        |
| `distancia_total_m` | NUMERIC(8,3) | Distância percorrida (metros)        |
| `duracao_min`       | NUMERIC(4,1) | Duração da sessão (minutos)          |
| `area_total_m2`     | NUMERIC(8,2) | Área total roçada (m²)               |

### Tabela `leituras_sensores`

Cada linha é uma leitura de sensor a cada 5 segundos durante a operação.

| Coluna               | Tipo          | Descrição                                  |
|----------------------|---------------|--------------------------------------------|
| `id`                 | SERIAL PK     | Identificador único da leitura             |
| `sessao_id`          | INT FK        | Referência à sessão (`sessoes_rocagem.id`) |
| `timestamp`          | TIMESTAMP     | Horário da leitura                         |
| `posicao_x_m`        | NUMERIC(8,3)  | Distância acumulada percorrida (metros)    |
| `altitude_z_m`       | NUMERIC(8,4)  | Altitude do robô em relação ao nível base  |
| `pitch_rad`          | NUMERIC(8,6)  | Inclinação do giroscópio (radianos)        |
| `dist_us_cm`         | NUMERIC(7,2)  | Leitura do sensor ultrassom (cm)           |
| `vibracao_g`         | NUMERIC(7,4)  | Intensidade de vibração (g)                |
| `desnivel_detected`  | BOOLEAN       | Verdadeiro quando desnível detectado       |

### Relacionamento

```
sessoes_rocagem (1) ──────── (N) leituras_sensores
     id                         sessao_id
```

Uma sessão possui muitas leituras; cada leitura pertence a uma sessão.

### Dados Utilizados

Os dados foram **simulados** com script Python (`simular.py`) representando três sessões de 10 minutos cada, com leituras a cada 5 segundos (120 leituras/sessão, 360 no total). O terreno foi modelado com variações sinusoidais e transições discretas de nível para representar diferentes perfis de acostamento.

| Sessão                   | Perfil do Terreno            | Desníveis |
|--------------------------|------------------------------|-----------|
| Trecho A - Plano         | Poucas variações             | 4         |
| Trecho B - Irregular     | Várias transições moderadas  | 15        |
| Trecho C - Alto Desnível | Transições severas           | 23        |

---

## 5 Perguntas e Consultas SQL

### Pergunta 1 — Qual o maior desnível que o robô enfrentou em cada sessão?

**Por que é útil para a empresa:** Informa a pior irregularidade de cada trecho, ajudando a empresa a entender quais trechos exigem mais robustez do robô e quais podem precisar de intervenção no acostamento.

**Consulta SQL:**

```sql
SELECT
    s.nome                                          AS sessao,
    ROUND(MAX(ABS(l.delta_z))::numeric, 4)         AS maior_desnivel_m
FROM (
    SELECT
        sessao_id,
        altitude_z_m - LAG(altitude_z_m) OVER (
            PARTITION BY sessao_id ORDER BY timestamp
        ) AS delta_z
    FROM leituras_sensores
) l
JOIN sessoes_rocagem s ON s.id = l.sessao_id
WHERE l.delta_z IS NOT NULL
GROUP BY s.id, s.nome
ORDER BY maior_desnivel_m DESC;
```

**Resultado:**

| sessao                  | maior_desnivel_m |
|-------------------------|------------------|
| Trecho C - Alto Desnivel| 0.3120           |
| Trecho B - Irregular    | 0.1732           |
| Trecho A - Plano        | 0.0816           |

**Interpretação:** O Trecho C apresentou o maior desafio de irregularidade com 31 cm de variação de nível enfrentada pelo robô. Os trechos com maior desnível exigem que o robô tenha amorteçamento e tração adequados. A empresa pode usar essas informações para priorizar trechos que precisam de manutenção do acostamento.

---

### Pergunta 2 — Quantos desníveis foram registrados em cada sessão?

**Por que é útil para a empresa:** Quantificar a frequência de transições de nível ajuda a empresa a comparar a complexidade dos trechos e planejar manutenção preventiva do equipamento (acumulo de desgaste em terrenos mais irregulares).

**Consulta SQL:**

```sql
SELECT
    s.nome                                          AS sessao,
    COUNT(*) FILTER (WHERE l.desnivel_detected)    AS qtd_desniveis
FROM sessoes_rocagem s
JOIN leituras_sensores l ON l.sessao_id = s.id
GROUP BY s.id, s.nome
ORDER BY qtd_desniveis DESC;
```

**Resultado:**

| sessao                  | qtd_desniveis |
|-------------------------|---------------|
| Trecho C - Alto Desnivel| 23            |
| Trecho B - Irregular    | 15            |
| Trecho A - Plano        | 4             |

**Interpretação:** O Trecho C registrou quase 6× mais desníveis que o Trecho A. Trechos com alta frequência de desníveis podem indicar degradação do acostamento ou geografia desfavorável, e a empresa pode decidir realizar campanhas de regularização nessas áreas.

---

### Pergunta 3 — Qual é a área total roçada por minuto em cada sessão?

**Por que é útil para a empresa:** Mede a produtividade operacional em m²/min. Permite comparar sessões e identificar se o robô está mantendo a taxa de produção esperada, ou se terrenos irregulares impactam a velocidade efetiva.

**Consulta SQL:**

```sql
SELECT
    s.nome                                          AS sessao,
    ROUND(s.area_total_m2 / s.duracao_min, 2)     AS area_m2_por_minuto
FROM sessoes_rocagem s
ORDER BY area_m2_por_minuto DESC;
```

**Resultado:**

| sessao              | area_m2_por_minuto |
|---------------------|--------------------|
| Trecho A - Plano    | 7.44               |
| Trecho B - Irregular| 5.95               |
| Trecho C - Alto Desnivel| 4.46           |

**Interpretação:** A velocidade de operação impacta diretamente a produtividade: o Trecho A (plano, 0,5 m/s) roça 7,44 m²/min; o Trecho C (desnível severo, 0,3 m/s) cai para 4,46 m²/min — uma redução de 40%. Em operação real, terrenos com muitos desníveis exigem redução de velocidade para segurança, reduzindo a produtividade. Esta consulta ajuda a empresa a estimar o tempo necessário para roçar trechos de extensão conhecida em função do perfil de terreno.

---

### Pergunta 4 — Quantos km o robô percorreu por minuto em cada sessão?

**Por que é útil para a empresa:** A velocidade média de deslocamento (km/min) é uma métrica de performance da operação. Ajuda a empresa a planejar a capacidade de roçagem por dia e a dimensionar a frota de robôs necessária para cobrir a extensão total dos acostamentos sob responsabilidade da concessionária.

**Consulta SQL:**

```sql
SELECT
    s.nome                                          AS sessao,
    ROUND(s.distancia_total_m / 1000.0 / s.duracao_min, 4)
                                                    AS km_por_minuto
FROM sessoes_rocagem s
ORDER BY km_por_minuto DESC;
```

**Resultado:**

| sessao              | km_por_minuto |
|---------------------|---------------|
| Trecho A - Plano    | 0.0298        |
| Trecho B - Irregular| 0.0238        |
| Trecho C - Alto Desnivel| 0.0179     |

**Interpretação:** O robô não manteve velocidade constante: o Trecho A (plano, 0,5 m/s) percorreu 0,0298 km/min; o Trecho B (irregular, 0,4 m/s) caiu para 0,0238 km/min; o Trecho C (alto desnível, 0,3 m/s) chegou a 0,0179 km/min — uma redução de 40% em relação ao Trecho A. A velocidade de operação impacta diretamente a distância percorrida por unidade de tempo. Em operação real, terrenos com muitos desníveis exigem redução de velocidade para segurança, reduzindo a produtividade. Esta consulta ajuda a empresa a estimar o tempo necessário para percorrer trechos de extensão conhecida em função do perfil de terreno e da velocidade configurada.

---

### Pergunta 5 — Qual o maior ângulo de inclinação (pitch) que o robô alcançou em cada sessão, em graus?

**Por que é útil para a empresa:** O pitch máximo indica a extremidade do esforço mecânico sofrido pelo robô. Valores elevados podem sinalizar risco de dano ao equipamento ou perda de estabilidade. A empresa pode usar essa informação para definir limites de operação ou para selecionar trechos que requerem nível diferente de robustez no robô.

**Consulta SQL:**

```sql
SELECT
    s.nome                                          AS sessao,
    ROUND((MAX(ABS(l.pitch_rad)) * 180.0 / PI())::numeric, 2)
                                                    AS maior_angulo_graus
FROM sessoes_rocagem s
JOIN leituras_sensores l ON l.sessao_id = s.id
GROUP BY s.id, s.nome
ORDER BY maior_angulo_graus DESC;
```

**Resultado:**

| sessao                  | maior_angulo_graus |
|-------------------------|--------------------|
| Trecho C - Alto Desnivel| 11.92              |
| Trecho B - Irregular    | 4.96               |
| Trecho A - Plano        | 1.87               |

**Interpretação:** O Trecho C exigiu o maior esforço do robô com 11,92° de inclinação, cerca de 6,4× mais que o Trecho A. Angulações acima de 5° já podem indicar risco de desestabilização em robôs de pequeno porte. O Trecho B registrou 4,96°, próximo ao limiar de atenção. A empresa deve considerar que trechos com desnível frequente geram mais stress no equipamento e planejar manutenção mais próxima para robôs que operam nesses trechos. Os valores de pitch também correlacionam com os desníveis detectados: onde o terreno é mais irregular, o giroscópio registra maior inclinação.

---

## Arquivos Entregues

```
.
├── README.md           ← este arquivo
├── banco-rocador.sql   ← criação das tabelas + \copy de carga + 5 consultas
├── simular.py          ← script Python que gerou os dados simulados
├── dados/
│   ├── sessoes.csv               ← resumo de 3 sessões
│   ├── leituras_sessao1.csv      ← 120 leituras (Trecho A)
│   ├── leituras_sessao2.csv      ← 120 leituras (Trecho B)
│   └── leituras_sessao3.csv      ← 120 leituras (Trecho C)
└── entrega.txt         ← nome, RM dos integrantes + link do GitHub
```

---

## Como Reproduzir

1. Execute o script de simulação para gerar os CSVs:

   ```bash
   python simular.py
   ```

2. Importe os dados no PostgreSQL (na mesma pasta do arquivo):

   ```bash
   psql -U seu_usuario -d seu_banco -f banco-rocador.sql
   ```

   Ou no pgAdmin: abra o Query Tool e use `\i banco-rocador.sql`.

3. Execute as consultas:

   ```bash
   psql -U seu_usuario -d seu_banco -c "SELECT ..."
   ```
