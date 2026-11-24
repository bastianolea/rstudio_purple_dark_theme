# Regenera los temas desde fuente y los aplica en RStudio
#
# Ejecutar después de actualizar RStudio, porque cada actualización cambia
# las clases necesarias para aplicar el tema.
#
# Si construir_tema() falla porque algún nombre ya no existe, usar `doctor()`

source("R/clases.R")
source("R/construir.R")
source("R/doctor.R")

# doctor()

construir_tema("light", instalar = TRUE)
construir_tema("dark", instalar = TRUE)
