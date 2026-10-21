# Week 1 Deployment Architecture

```text
Windows browser (client)
        | HTTP :80
        v
Ubuntu VM (VMware bridged network)
  Nginx :80 (public VM interface)
        | reverse proxy
        v
  Gunicorn + Flask 127.0.0.1:8000
        | PostgreSQL connection
        v
  PostgreSQL 127.0.0.1:5432
        | persistent DB files
        v
  Ubuntu virtual disk

GitHub Repository -> manual git clone / pull -> Ubuntu VM
SSH :22 (admin only); UFW allows selected ports.
```
