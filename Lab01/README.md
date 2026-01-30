---
config:
  layout: fixed
---
flowchart TB
    A["1. Prisijungti prie Azure Portalo"] --> B["2. Pervadinti prenumeratą<br>Grupė-Vardas-Pavardė"]
    B --> C["3. Suteikti prieigą dėstytojui<br>Rolė: Contributor"]
    D["4. Atsakyti į papildomus klausimus"] --> E["5. Paleisti tikrinimo skriptą<br>irm ... | iex"]
    C --> D

    style A fill:#5FA7FF,stroke:#365F91,stroke-width:2px
    style B fill:#5FA7FF,stroke:#365F91,stroke-width:2px
    style C fill:#5FA7FF,stroke:#365F91,stroke-width:2px
    style E fill:#5FA7FF,stroke:#365F91,stroke-width:2px
    style D fill:#dff0d8,stroke:#3c763d,stroke-width:2px