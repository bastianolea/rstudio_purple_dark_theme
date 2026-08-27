# Regenera los temas desde fuente/ y aplica el oscuro en RStudio.
#
# Correr esto después de actualizar RStudio: las clases del chrome del IDE
# cambian de nombre en cada versión y acá se resuelven de nuevo.
#
# Los temas generados llevan un "2" al final para poder tenerlos instalados
# junto a los anteriores hechos a mano y comparar. Cuando ya no haga falta,
# pasar sufijo = "" acá (y borrar los .rstheme viejos).
#
# Si construir_tema() falla porque algún nombre ya no existe, `doctor()`
# muestra el panorama y `buscar_miembro()` ayuda a encontrar el nombre nuevo.

source("R/mapa-clases.R")
source("R/construir.R")
source("R/doctor.R")

construir_tema("dark", instalar = TRUE)
construir_tema("light", instalar = TRUE)

# buscar_clase("GFRCULXJQ")
