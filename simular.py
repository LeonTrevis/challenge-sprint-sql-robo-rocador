#!/usr/bin/env python3
"""
Simulação de dados de sensores de um robô de roçagem de grama
para o projeto de SQL Aplicado ao Challenge.

Gera 3 sessões de 10 minutos cada, com leituras a cada 5 segundos.
"""

import csv
import math
import random
import os
from datetime import datetime, timedelta

# =============================================================================
# PARÂMETROS DA SIMULAÇO
# =============================================================================
LEMBRETE = 5             # segundos entre leituras
DURACAO_SESSAO_S = 600   # 10 minutos
LARGURA_ROÇAGEM_M = 0.25  # 25 cm
SEED = 42                # semente para reprodutibilidade

TIMESTAMP_INICIO = datetime(2025, 9, 15, 8, 0, 0)  # 15/09/2025 08:00
GAP_ENTRE_SESSOES_S = 600  # 10 min entre o fim de uma e início da próxima

# =============================================================================
# GERAÇÃO DE TERRENO
# =============================================================================

def sin_terreno(x_m, freq_hz=0.01, amp_m=0.15):
    """Variacao sinusoidal suave do terreno."""
    return amp_m * math.sin(2 * math.pi * freq_hz * x_m)

def nivel_transicoes(x_m, nivel_base=0.0, transicoes=[]):
    """
    Transicoes entre niveis (saltos).
    transicoes = [(posicao_m, delta_altitude_m), ...]
    """
    z = nivel_base
    for pos, delta in transicoes:
        if x_m >= pos:
            z += delta
    return z

# =============================================================================
# SESSOES
# =============================================================================
SESSOES = [
    {
        "id": 1,
        "nome": "Trecho A - Plano",
        "velocidade_m_s": 0.5,   # mais rápida: terreno plano
        "nivel_base": 0.0,
        "transicoes": [
            (50, 0.05),    # desnivel leve em 50m
            (180, -0.04),  # leve reducao em 180m
            (270, 0.06),   # leve subida em 270m
        ],
        "ruido_std": 0.02,
    },
    {
        "id": 2,
        "nome": "Trecho B - Irregular",
        "velocidade_m_s": 0.4,   # mais lenta: terreno irregular
        "nivel_base": 0.1,
        "transicoes": [
            (30, 0.15),
            (90, -0.10),
            (150, 0.20),
            (210, -0.15),
            (260, 0.12),
        ],
        "ruido_std": 0.03,
    },
    {
        "id": 3,
        "nome": "Trecho C - Alto Desnivel",
        "velocidade_m_s": 0.3,   # mais lenta ainda: desnivel severo
        "nivel_base": -0.05,
        "transicoes": [
            (20, 0.30),
            (80, -0.25),
            (140, 0.35),
            (200, -0.30),
            (250, 0.28),
            (290, -0.20),
        ],
        "ruido_std": 0.04,
    },
]

os.makedirs("dados", exist_ok=True)

# =============================================================================
# SIMULACAO
# =============================================================================

def simular_sessao(sessao, csv_path):
    """Gera leituras para uma sessao e salva em CSV."""
    transicoes = sorted(sessao["transicoes"], key=lambda t: t[0])
    total_leituras = DURACAO_SESSAO_S // LEMBRETE

    ultimo_nivel = None  # nivel base (incluindo transicoes ate o momento)
    max_desnivel = 0.0
    ultimo_z = None

    with open(csv_path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow([
            "timestamp", "posicao_x_m", "altitude_z_m",
            "pitch_rad", "dist_us_cm", "vibracao_g",
            "desnivel_detected",
        ])

        for i in range(total_leituras):
            t = i * LEMBRETE
            timestamp = TIMESTAMP_INICIO + timedelta(seconds=t)
            vel = sessao["velocidade_m_s"]
            pos_x = t * vel

            # Altitude do terreno
            z_sin = sin_terreno(pos_x)
            z_nivel = nivel_transicoes(pos_x, sessao["nivel_base"], transicoes)
            z_ruido = random.gauss(0, sessao["ruido_std"])
            z = z_nivel + z_sin + z_ruido

            # Pitch do giroscopio (rad): derivada da altitude / distancia percorrida
            # Usa diferenca de altitude / distancia percorrida no intervalo
            if i > 0 and ultimo_z is not None:
                pos_anterior = (i - 1) * LEMBRETE * vel
                pitch = (z - ultimo_z) / (pos_x - pos_anterior)
                pitch = max(-0.5, min(0.5, pitch))  # clamp
            else:
                pitch = 0.0

            # Distancia ultrassom (cm): |z| com ruído
            dist_us = abs(z) * 100 + random.gauss(0, 1.0)
            dist_us = max(0, dist_us)

            # Vibracao (g): correlacionada com |pitch| e desnivel
            vib = abs(pitch) * 8 + abs(z - z_nivel) * 15
            vib = min(5.0, vib)

            # Deteccao de desnivel: |Δz| entre leituras consecutivas > threshold
            desnivel = False
            if ultimo_z is not None:
                delta_z = abs(z - ultimo_z)
                desnivel = delta_z > 0.07  # 7 cm de variacao = desnivel
                if delta_z > max_desnivel:
                    max_desnivel = delta_z

            writer.writerow([
                timestamp.isoformat(),
                round(pos_x, 3),
                round(z, 4),
                round(pitch, 6),
                round(dist_us, 2),
                round(vib, 4),
                desnivel,
            ])

            ultimo_z = z

    print(f"  Sessao '{sessao['nome']}' ({total_leituras} leituras): "
          f"max_desnivel={max_desnivel:.3f}m gravado")

# =============================================================================
# RESUMO
# =============================================================================
def gerar_resumo(sessoes, csv_dir):
    """Gera CSV de resumo das sessoes."""
    resumo = []
    for idx, s in enumerate(sessoes):
        # Cada sessão começa após a anterior + gap
        offset_s = idx * (DURACAO_SESSAO_S + GAP_ENTRE_SESSOES_S)
        data_inicio = TIMESTAMP_INICIO + timedelta(seconds=offset_s)
        csv_path = os.path.join(csv_dir, f"leituras_sessao{s['id']}.csv")
        leituras = []
        with open(csv_path, "r") as f:
            reader = csv.DictReader(f)
            for row in reader:
                leituras.append(row)

        distancia_total = float(leituras[-1]["posicao_x_m"])
        duracao_min = len(leituras) * LEMBRETE // 60
        area_total = distancia_total * LARGURA_ROÇAGEM_M
        pitch_rads = [float(r["pitch_rad"]) for r in leituras]
        max_pitch_deg = max(abs(p) for p in pitch_rads) * 180 / math.pi
        alturas = [float(r["altitude_z_m"]) for r in leituras]
        max_altura = max(alturas)
        deltas = [abs(alturas[i] - alturas[i-1])
                  for i in range(1, len(alturas))]
        max_desnivel = max(deltas) if deltas else 0.0
        desnivel_count = sum(1 for r in leituras
                            if r["desnivel_detected"] == "True")

        resumo.append({
            "id": s["id"],
            "nome": s["nome"],
            "data_inicio": data_inicio.isoformat(),
            "data_fim": (data_inicio + timedelta(seconds=DURACAO_SESSAO_S)).isoformat(),
            "distancia_total_m": round(distancia_total, 3),
            "duracao_min": duracao_min,
            "area_total_m2": round(area_total, 2),
            "max_pitch_deg": round(max_pitch_deg, 2),
            "max_altura_m": round(max_altura, 4),
            "max_desnivel_m": round(max_desnivel, 4),
            "n_desniveis": desnivel_count,
        })

    with open(os.path.join(csv_dir, "sessoes.csv"), "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=resumo[0].keys())
        writer.writeheader()
        writer.writerows(resumo)

    for r in resumo:
        print(f"  Resumo sessao {r['id']}: "
              f"dist={r['distancia_total_m']}m, "
              f"area={r['area_total_m2']}m2, "
              f"pitch_max={r['max_pitch_deg']}°, "
              f"alt_max={r['max_altura_m']}m, "
              f"desnivel_max={r['max_desnivel_m']}m, "
              f"n_desniveis={r['n_desniveis']}")
    print()


# =============================================================================
# MAIN
# =============================================================================
if __name__ == "__main__":
    random.seed(SEED)
    print("=" * 60)
    print("Simulacao de sensores - Robô de Roçagem de Grama")
    print(f"  Leituras a cada {LEMBRETE}s | Sessões de {DURACAO_SESSAO_S}s")
    velocidades = [s["velocidade_m_s"] for s in SESSOES]
    print(f"  Velocidades: {', '.join(f'{v} m/s' for v in velocidades)} | Largura: {LARGURA_ROÇAGEM_M} m")
    print("=" * 60)
    print()

    for s in SESSOES:
        csv_path = os.path.join("dados", f"leituras_sessao{s['id']}.csv")
        print(f"Gerando sessao {s['id']}: {s['nome']}...")
        simular_sessao(s, csv_path)
    print()

    print("Gerando resumo das sessoes...")
    gerar_resumo(SESSOES, "dados")
    print("Concluido. Dados salvos em 'dados/'.")
