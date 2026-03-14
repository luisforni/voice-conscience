# SETUP: Crear repos y registrar submódulos

1. Crear tres repos en GitHub:
   - voice-conscience (repo raíz)
   - voice-conscience-backend
   - voice-conscience-mobile

2. En el repo raíz (`voice-conscience`) añadir los submódulos:
   ```bash
   git submodule add https://github.com/your-org/voice-conscience-backend.git services/backend
   git submodule add https://github.com/your-org/voice-conscience-mobile.git apps/mobile
   git commit -m "Add backend and mobile submodules"
   git push origin main
   ```

3. Para clonar con submódulos:
   ```bash
   git clone --recursive <repo-root-url>
   # o si ya clonaste
   git submodule init
   git submodule update --remote --recursive
   ```

4. Workflow recomendado:
   - Trabajar en `services/backend` y `apps/mobile` como repos independientes.
   - En el repo raíz mantener documentación, scripts de orquestación y referencias.
