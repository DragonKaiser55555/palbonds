> # ⛔ HISTORY ONLY — NEVER READ THIS FILE FOR STATUS
>
> Every section below is a dated record of what was true **on that day**. Many of
> them describe problems that have since been fixed and shipped, in wording that
> reads as if the problem is current. A session that takes status from here will
> tell Dragón that solved work is still open — which is exactly what happened on
> 2026-09-28 and is why this file exists in its present form.
>
> **What is open, what is closed, and every rule that still binds live in
> `CLAUDE.md`, which is short enough to read completely in one call.** Come here
> only to answer "how was this done?" or "was this already tried?", and treat
> anything you find as evidence about the past, never as a task.

# PalBonds — Historial de sesiones archivado (Continuación 1 a 154)

Este archivo existe por un pedido explícito de Dragón (2026-09-06): `CLAUDE.md` había crecido tanto (más de 460KB) que ya superaba el límite de lectura de una sola llamada — un riesgo real de que una sesión futura no viera contenido importante. Este archivo contiene el historial narrativo COMPLETO de las sesiones 2026-09-01 a 2026-09-05 (desde el arranque del proyecto hasta la Continuación 154), movido tal cual desde `CLAUDE.md` — nada se resumió ni se borró, solo se relocalizó.

**No hace falta leer este archivo para continuar el trabajo del proyecto.** `CLAUDE.md` (el archivo activo) ya tiene todo lo necesario para retomar: la tabla de progreso, la lista "EMPEZAR ACÁ" con el estado más reciente, y las últimas ~16 continuaciones (155 en adelante), que cubren todo el trabajo activo actual (investigación de balance, la saga del retraso de captura, la saga de follow/interrupt). Consultar este archivo solo si se necesita el detalle exacto de una decisión o hallazgo de una sesión vieja (por ejemplo, "¿cuándo se confirmó tal función nativa?").

El detalle técnico línea-por-línea de log de estas mismas sesiones vive en `docs/hook-points.md` (y su propio archivo `docs/hook-points-archive.md`, mismo criterio de división).

---

## Sesión del 2026-09-01 (continuación): Trust/Combat/Capture reales

Dragón dio la especificación completa de cómo debería funcionar la confianza (basada en el sistema real de Palworld: rango 0-10, más puntos necesarios por rango, bonos de stats, ganancia pasiva en party/base, "kinship peaches", accesorios) más las reglas propias del mod (5 interacciones exitosas -> empieza a seguir, ganancia pasiva mientras sigue, pérdida grande de confianza si recibe daño, huida permanente si llega a 0, pérdida total si el jugador se aleja demasiado, captura sin esfera al llegar a rango 1).

Se confirmó en el SDK real: `GetFriendshipRank()` (el rango 0-10 real, mismo objeto que ya usábamos para `GetFriendshipPoint()`), la tabla de puntos requeridos por rango (`FPalFriendshipRankDataRow`), y los campos reales de auto-incremento pasivo por estar en party/base. Se implementó una primera versión real y funcional de `Trust.lua` (ya no es un stub): cuenta interacciones exitosas, dispara "empezar a seguir" a las 5, dispara "capturar aquí" al llegar a rango 1 (la captura en sí todavía no está implementada — ver abajo), y aplica pérdida de confianza real por daño o por alejarse demasiado del jugador.

`Combat.lua` ahora intenta un "seguimiento" aproximado usando una función de movimiento real del juego (`PalMoveToLocation`) reenviada cada pocos segundos — no es el sistema real de Otomo (eso sigue sin resolverse, pregunta 6), así que es una aproximación a probar en vivo, no la cosa real todavía.

`Capture.lua` ahora marca permanentemente a un Pal que perdió toda su confianza (y `Interaction.lua` ya rechaza interactuar con uno así) — pero la llamada real de captura sin esfera (pregunta 4) sigue sin implementarse, solo el disparador.

Novedad técnica: esta es la primera vez que el mod usa un temporizador repetitivo (no solo hooks de eventos) — UE4SS expone `ExecuteInGameThreadWithDelay`/`LoopAsync`, pero el propio motor advierte que el primero puede fallar en detectar el punto de enganche necesario según la versión del juego. Está probado con manejo de errores y un respaldo automático, pero **todavía no confirmado en vivo** — es lo primero a revisar en el próximo test (buscar líneas "[TICK]" en el log).

Sin implementar todavía: el kinship peach (necesita el nombre real del ítem), que los Pals que siguen ayuden en combate, y que un Pal que perdió toda confianza realmente huya/desaparezca (por ahora solo deja de seguir y de ser interactuable).

## Sesión del 2026-09-01 (continuación 2): por qué el seguimiento se sentía irregular, y por qué no se pudo confirmar la pérdida de confianza por daño

Dragón hizo una sesión de prueba completa: 2 Lambals y una Caprity llegaron a seguir al jugador tras 5 interacciones, pero las tres "perdieron interés y se alejaron" o (la Caprity) "salió corriendo con su comportamiento asustadizo normal" antes de que el jugador se acercara. Un tercer Lamball ("Lamball 3") llegó a la interacción #9, se usó para provocar una pelea contra otro Lamball (con un Gumoss salvaje sumándose), ganó la pelea, "nunca huyó pese a recibir varios golpes y casi morir", y después se alejó por su cuenta. Conclusión de Dragón: no tiene sentido seguir probando eventos de daño/distancia/captura mientras el seguimiento en sí sea poco confiable.

**Revisando el log real (`palbonds-live.log` + `UE4SS.log`, ambos en la instalación real del juego) se confirmaron dos cosas buenas que el reporte no dejaba ver:** el temporizador `[TICK]` (`ExecuteInGameThreadWithDelay`) funcionó de forma estable toda la sesión (primera vez confirmado en vivo), y las tres "pérdidas de interés" fueron exactamente el mecanismo de pérdida de confianza por distancia funcionando como se diseñó (`AddFriendShip` con `-38`, `-22`, `-76` — vaciando el punto total real justo cuando cada Pal superó `MAX_FOLLOW_DISTANCE`), no un bug.

**Sobre la pelea de Lamball 3: nunca quedó registrada.** Ambos archivos de log — el nuestro y el propio de UE4SS — se cortan exactamente en el mismo timestamp (`17:51:16`), quince segundos después de la interacción #9 de Lamball 3. No hay ninguna línea de ningún mod después de ese momento. Es decir, toda la pelea (provocar a Lamball 4, la pelea en sí, el Gumoss uniéndose, Lamball 3 casi muriendo, y alejándose después) pasó después de que el registro — y probablemente UE4SS entero, quizás el juego mismo — dejara de escribir. Se confirmó que el hook de daño (`PalHate:DamageEvent`) sí se instaló bien (el mensaje de error de instalación nunca aparece en el log), simplemente no hay datos del único período que lo habría puesto a prueba. Pendiente: repetir la prueba y confirmar que el juego/log no se corte de nuevo durante una pelea real.

**El fix real de esta sesión — por qué el seguimiento se sentía irregular:** dos causas reales, ambas corregidas: (1) la orden de movimiento solo se reenviaba cada 5 segundos (`Trust.lua`), dejando tiempo de sobra para que la IA salvaje propia del Pal (vagar/pastar/huir) tomara el control entre una orden y la siguiente — bajado a 1.5 segundos. (2) Nuevo, sin confirmar en vivo todavía: `Combat.lua` ahora llama `APalAIController:SetActiveAI(false)` mientras el Pal está siguiendo (y `SetActiveAI(true)` al dejar de seguir, sea por corte suave o huida permanente), para intentar frenar del todo la toma de decisiones de la IA salvaje mientras dura el vínculo. Es una función real ya vista en el SDK pero nunca llamada hasta ahora — mismo tipo de llamada simple (bool, sin retorno) que ya se probó segura antes, pero el resultado real (si mejora el seguimiento, o si en cambio deja al Pal completamente quieto) todavía no se probó en vivo.

## Sesión del 2026-09-01 (continuación 3): el fix de SetActiveAI salió mal — revertido con evidencia real

El intento anterior de "arreglar" el seguimiento (`SetActiveAI(false)` mientras el Pal sigue) resultó ser un error real, confirmado con la siguiente sesión de prueba de Dragón: los Pals que ya seguían dejaron de ejecutar la animación real de acariciar/alimentar (solo seguía apareciendo la sonrisa de "Happy", una llamada distinta) y, peor, dejaron de reaccionar del todo al recibir daño de otros Pals salvajes — uno murió sin hacer nada, otro se quedó parado recibiendo golpes sin huir ni pelear. `SetActiveAI(false)` no es un interruptor fino de "no vagues" — parece apagar toda la capa de decisión de IA del Pal, incluyendo sus reacciones normales de pelea/huida que existirían sin nuestro mod. Se revirtió por completo esa llamada de `Combat.lua`; se mantiene el tick más rápido (1.5s) de la sesión anterior, que no está implicado en el problema.

Dentro de la misma sesión de prueba, sí se confirmó que el hook de daño real (`PalHate:DamageEvent`) funciona: un PlantSlime que seguía recibió daño real, aplicó la penalización de confianza, llegó a rango 0, y disparó correctamente "ya no sigue" → "perdió toda la confianza — huye para siempre" — el problema nunca fue la matemática de confianza, solo el efecto secundario de apagar la IA.

Dos ajustes más de esta sesión, con números reales de Dragón: la penalización por recibir daño bajó de -50 a -25 (Dragón: "si acariciar/alimentar da 10 cada uno, recibir un golpe — del jugador o de otro Pal — debería quitar 25"), y se agregó un log incondicional de cada `DamageEvent` real (con quién atacó, a quién, y cuánto daño) para poder confirmar directamente en la próxima sesión si golpear al propio Pal que sigue también le quita confianza (en teoría ya debería funcionar, el hook nunca filtró por atacante, pero después de esta ronda de sorpresas se prefiere confirmarlo con datos en vez de asumirlo).

## Sesión del 2026-09-01 (continuación 4): investigación real con FModel, a pedido de Dragón

Dragón hizo una observación clave: seguíamos "peleando contra la IA propia del Pal" en vez de realmente hacerlo entrar al sistema real de Pals de party, y lo mismo con acariciar/alimentar salvajes — estábamos evitando el sistema real en vez de habilitarlo. Pidió investigar más a fondo antes de seguir parchando. Con FModel ya conectado (antes no se tenía acceso), se investigó por primera vez el sistema real de seguimiento de Otomo (Pals de party).

Se encontró la clase Blueprint real que usan los Pals de party para seguir: `BP_MonsterAIController_Otomo` (extiende la misma clase base nativa, `PalAIController`, que ya tienen los Pals salvajes). Tiene un componente de seguimiento real (`PalFollowingComponent`, que resulta ser solo una variante vacía del sistema de movimiento estándar de Unreal — es decir, nuestra propia aproximación con `PalMoveToLocation` ya usa el mismo tipo de movimiento real, no hay nada exótico ahí) y un módulo de combate real (`PalAICombatModule_Otomo`) que hereda funciones reales y llamables para asistir en combate (`AIMoveToTargetActor`, `GetTargetActor`, `IsBattleMode`) — respuesta directa a "si el jugador ataca, que ayuden".

El problema real: nada en ningún Blueprint del juego asigna esa clase de controller a un Pal — se buscó con la función de "buscar referencias" de FModel contra los 93.800 paquetes cargados y no apareció ninguna. La asignación real pasa por código C++ nativo no inspeccionable, no por un interruptor de Blueprint que se pueda simplemente activar. Convertir un Pal salvaje en un Otomo real significaría forzar un re-posesionamiento en vivo (despojar el controller actual, crear uno nuevo de esa clase, poseer con él, y configurar a mano su `OtomoSlotIndex`/`CombatModuleClass`) — una categoría de operación nueva y más riesgosa que cualquier otra intentada en este proyecto hasta ahora. No se intentó esta sesión; queda documentado como el próximo experimento concreto, aislado y muy loggeado, antes de tocar `Combat.lua`.

Sobre acariciar/alimentar salvajes: se reconfirmó desde el lado nativo que la función real (`GetIndicatorInfo`) es pura interfaz de Blueprint sin cuerpo nativo — no existe una función nativa tipo "es dueño de este Pal" que se pueda leer. Falta encontrar qué Blueprint específico implementa esa función para un `PalCharacter` genérico (la búsqueda directa por ese nombre no encontró nada) — ese es el próximo paso concreto para esa mitad de la investigación.

## Sesión del 2026-09-01 (continuación 5): ¿alguien más ya encontró esto? ¿y si está del lado del jugador?

Dragón preguntó dos cosas directas: si ya se había buscado esto online (alguien más pudo haberlo resuelto ya), y si tal vez el sistema real no está en el Pal sino en el jugador o en el archivo de guardado. Ambas se investigaron a fondo.

**Búsqueda online:** un sitio real de documentación de modding (pwmodding.wiki) confirma un componente Blueprint real, `BP_OtomoPalHolderComponent`, con una función `ActivateOtomo(SlotID, Transform, &IsSuccess)` — coincide con el nombre "OtomoHolder" que después se confirmó también del lado nativo. No se encontró ningún mod público que ya resuelva esto de punta a punta (los mods de captura sin esfera existentes no hacen esto — solo fuerzan el check de captura normal a que siempre tenga éxito). Tampoco hay documentación pública sobre el gate de acariciar/alimentar — parece territorio genuinamente sin explorar públicamente, no solo algo que no habíamos encontrado.

**¿Está del lado del jugador?** Sí, confirmado. El repositorio público `cheahjs/palworld-save-tools` (una herramienta real y usada para leer archivos de guardado de Palworld) confirma que la membresía de party/base/caja es un registro de guardado (contenedor + slots, cada slot con `{player_uid, instance_id, permiso}`), no una propiedad del Pal en sí. Y confirmado directo en el SDK nativo del juego: `FPalWorldPlayerSaveData` (la estructura de guardado DEL JUGADOR) tiene un campo real, `OtomoCharacterContainerId`, apuntando a su contenedor de party. Exactamente lo que Dragón sospechaba.

Mejor aún: se encontró una clase nativa completa, `UPalOtomoHolderComponentBase` (obtenible con `GetOtomoHolder(PlayerState)`), con funciones reales que parecen ser justo la API que necesitamos: `AddOtomoHandleToFreeSlot(handle)` para meter un Pal al contenedor, y `ActivatePalByHandle(...)`/`ActivateCurrentOtomo(...)` para hacerlo aparecer/poseerlo — presumiblemente la MISMA función que usa el juego cuando el jugador saca un Pal de su esfera. Si es así, dejaría que el propio código ya probado del juego asigne el controller correcto, en vez de que nosotros lo hagamos a mano (que era el plan anterior, más riesgoso).

Falta un dato antes de poder probar esto: cómo convertir un Pal salvaje (que hoy solo nos da un `UPalIndividualCharacterParameter`) en el `UPalIndividualCharacterHandle` que estas funciones piden. Ese es el próximo paso de investigación concreto — ver "Próximos pasos" arriba.

## Sesión del 2026-09-01 (continuación 6): se cierra el eslabón que faltaba, y aparece un segundo sistema real que Dragón señaló

Dragón pidió seguir investigando hasta tener confianza real de que algo puede funcionar, y sugirió mirar a Daedream, Dazzi y Flopie — Pals que Dragón ha visto seguir al jugador sin ser el Pal activo principal — como posible pista de cómo el juego maneja esto por dentro.

**El eslabón que faltaba (de la sesión anterior) ya se encontró.** Toda la cadena de funciones útiles pedía un `UPalIndividualCharacterHandle`, pero de un Pal salvaje solo podíamos sacar un tipo distinto (`UPalIndividualCharacterParameter`). Apareció `UPalUtility.GetIndividualCharacterHandleByActor(Actor)` — una función global (mismo tipo de función ya usada y confirmada segura antes, como `GetMinFriendshipRank()`), que convierte cualquier actor de Pal directamente en su handle, sin buscar ningún objeto intermedio. También apareció una forma más simple de conseguir el "holder" de party del jugador (`UPalUtility.GetOtomoHolderComponent(jugador)`) — la función encontrada la sesión pasada (`GetOtomoHolder(PlayerState)`) resultó pertenecer a una clase exclusiva del modo Arena/PvP, no de uso general como se pensó.

Con esto, la cadena completa de funciones reales para intentar convertir un Pal salvaje en un Otomo real queda armada de punta a punta (ver `hook-points.md`, "Twenty-first pass" para la secuencia exacta) — **todavía sin probar en vivo**. Es la hipótesis mejor fundamentada que ha tenido este proyecto hasta ahora sobre este tema, pero sigue siendo una hipótesis, no un hecho confirmado.

**Sobre Daedream/Dazzi/Flopie: la pista de Dragón resultó real.** Se encontró una clase nativa, `UPalPlayerPartyPalHolder`, con dos campos reales `FirstOtomoPal`/`SecondOtomoPal` (además de una lista de banca) — confirmación directa, del lado nativo del juego, de que existen DOS espacios de Pal activo simultáneos, no solo uno, más una función `ChangePalSlot(bool SecondPal)` para manejarlos independientemente. Esto encaja exactamente con lo que Dragón describió (un Pal que sigue sin ser "el" Pal principal). Todavía no se encontró qué decide, por especie, cuáles Pals califican para ese segundo espacio (revisado directamente en la tabla de datos por especie y no está ahí — probablemente vive en las tablas de "Partner Skill" encontradas esta misma sesión, sin inspeccionar todavía en detalle) — no es crítico para el objetivo del proyecto, pero confirma que todo este sistema de "handles" es real y central, no un atajo secundario.

**Próximo paso real**: un experimento aislado, con una tecla de prueba dedicada y mucho logging, sobre un solo Pal vinculado — ver el plan de prueba paso a paso en `hook-points.md`. Pendiente de que Dragón lo autorice antes de intentarlo (igual que cada categoría de riesgo nueva en este proyecto).

## Sesión del 2026-09-02 (continuación 7): se confirma en vivo la secuencia real de cambio de Pal activo

Dragón hizo varias pruebas reales (cambiar de Pal activo varias veces, alternando entre Tanzee/Daedream/Dazzi/Flopie, con acariciadas y alimentadas de por medio) con el sistema de observación (`OtomoWatch.lua`) ya corregido de la sesión anterior (el hook que antes fallaba por intentar engancharse antes de que la clase existiera en memoria, ahora reintenta cada pocos segundos hasta lograrlo).

**Resultado: la secuencia real quedó confirmada, cuatro veces seguidas, siempre igual:** `holder:InactivateCurrentOtomo()` inmediatamente seguido de `holder:ActivateOtomo(slot, transform, éxito)`. Ninguna de las funciones encontradas la sesión anterior (`ActivatePalByHandle`, `ActivateCurrentOtomo`, `ChangePalSlot`) se disparó ni una sola vez — el camino real es otro, uno que recién se pudo ver una vez arreglado el problema de que la clase de Blueprint del jugador no estaba cargada en memoria al momento de instalar el hook.

También se vio que `SpawnOtomo` se dispara seguido pero parece ser solo para dibujar las vistas previas del menú (el Pal realmente activo nunca cambiaba entre esos llamados) — no es la activación real.

**Lo único que sigue sin confirmarse**: qué función se dispara cuando un Pal se une por primera vez a la party (al capturarlo). `AddOtomoHandleToFreeSlot` (la función que se esperaba que hiciera esto) nunca se disparó para el jugador en toda la sesión — ni cambiando de Pal, ni acariciando, ni alimentando, ni abriendo la Palbox. Solo se vio una vez, para un NPC, en una sesión anterior. Ese es el último hueco real antes de poder probar algo con un Pal salvaje con confianza genuina.

**De regalo**: se confirmaron los nombres internos reales de los Pals de Dragón — Tanzee = `BP_Monkey_C`, Flopie = `BP_FlowerRabbit_C`, Dazzi = `BP_DreamDemon_C`, Daedream = `BP_FlowerDoll_BOSS_C`.

**Próximo paso pedido a Dragón**: capturar un Pal salvaje nuevo, de forma completamente normal (con esfera, como siempre), con el sistema de observación activo — para ver si `AddOtomoHandleToFreeSlot` por fin se dispara para el jugador, y con qué datos exactos. Sigue siendo pura observación, cero riesgo nuevo.

**Corrección de Dragón (mismo día)**: no tiene a Dazzi en su party — los Pals reales son Tanzee=`BP_Monkey_C`, Flopie=`BP_FlowerRabbit_C`, Daedream=`BP_DreamDemon_C`, Petallia=`BP_FlowerDoll_BOSS_C` (el sufijo "_BOSS_" es porque esa Petallia específica es una Pal Alpha, la versión "jefe" de la especie, no una clase especial de party). Además, Dragón explicó qué pasaba realmente en pantalla: Daedream y Flopie tienen una habilidad de compañero que las hace seguir como secundarias, y CADA vez que se cambia de Pal activo, las secundarias también desaparecen y vuelven a aparecer, no solo el Pal al que se cambió. Esto corrige la lectura anterior de `SpawnOtomo` como "solo vista previa de menú" — en realidad probablemente sea la función real de "hacer que el Pal de este espacio de party exista en el mundo," usada tanto para el Pal activo como para las secundarias con habilidad de seguimiento — un segundo candidato real (más simple que `ActivateOtomo`) para cuando llegue el momento de probar algo con un Pal salvaje.

## Sesión del 2026-09-02 (continuación 8): prueba de captura real (resultado negativo pero útil) y la pregunta de Dragón sobre el método de investigación

Dragón hizo la prueba de captura pedida: guardó toda su party en la Palbox, capturó un Lamball macho (lo sacó y lo volvió a guardar), capturó un Lamball hembra, y volvió a sacar al macho para acariciarlo. Todo leído directo de `palbonds-live.log`.

**Buena noticia**: `ActivateOtomo`/`SpawnOtomo` funcionan perfecto sobre un Pal recién capturado, con su handle y su actor ya resueltos — la activación no distingue entre un Pal "viejo" en la party y uno que se acaba de unir hace segundos.

**Mala noticia, pero es un dato real, no un vacío**: `AddOtomoHandleToFreeSlot` siguió sin dispararse para el jugador, ni una sola vez, en dos capturas reales. Investigando por qué: la clase real de la party (`UPalIndividualCharacterContainer`) solo tiene funciones para LEER (`FindEmptySlot`, `FindByHandle`, `Get`, `Num`) — no existe ninguna función para agregar/asignar. Y cada espacio de la party (`UPalIndividualCharacterSlot`) tiene un campo `Handle` que se puede escribir directamente, sin ninguna función de por medio. Hipótesis actual: el paso real de "unirse a la party" es una escritura directa de ese campo en código nativo compilado — algo que ningún hook de función puede llegar a ver, sin importar cuánto busquemos.

**La pregunta de Dragón**: en vez de seguir espiando funciones/clases puntuales que suponemos que son las correctas, ¿por qué no capturar el log completo de todo lo que hace el juego y buscar ahí las funciones correctas? Pregunta justa, se investigó en serio en vez de descartarla:

- Se confirmó, contra la documentación oficial de UE4SS (docs.ue4ss.com), que `RegisterHook` en Lua SIEMPRE necesita el nombre exacto de una función — no existe un modo "enganchar todo" ni comodines.
- El hook interno de UE4SS que sí intercepta TODAS las llamadas a nivel de motor (`HookUObjectProcessEvent`, ya activado en la configuración) no está expuesto a Lua como una herramienta aparte — es lo que UE4SS usa por dentro para que `RegisterHook` funcione en funciones de Blueprint, no algo que podamos usar nosotros directamente para loguear todo.
- Conclusión honesta: "loguear literalmente todo" no es posible desde Lua en este mod — necesitaría cambiar UE4SS en C++, y aun así el volumen de datos (cada llamada a función de todo el motor, cada frame) sería un problema en sí mismo, más grande que el que tenemos ahora.

**Pero la idea de fondo sí sirvió, aplicada a algo que ya teníamos**: en vez de suponer un nombre de clase primero, se hizo una búsqueda amplia sobre el volcado completo de cabeceras (`CXXHeaderDump/Pal.hpp`, ~40,000 líneas) por las palabras "Capture" y "Handle", en vez de solo mirar las clases ya conocidas. Esto encontró dos candidatos mucho más prometedores para el momento exacto de "captura exitosa" que nunca habían aparecido en las búsquedas anteriores, porque ninguno usa el vocabulario "Otomo"/"Party" que se venía buscando:

- `UPalUtility::PalCaptureSuccess(AttackerPlayer, Monster)` — función estática global, de la misma clase ya confiable que dio `GetIndividualCharacterHandleByActor`.
- `APalCaptureJudgeObject::OnCaptureSuccess(Character, Result)` — el objeto que confirma el éxito de la esfera de captura del lado del servidor.

Ambas agregadas como observación de solo lectura (sin riesgo) a `OtomoWatch.lua`, desplegadas ya al juego y al mirror. Todavía no probadas en vivo.

**Próximo paso pedido a Dragón**: una captura real más, cualquier Pal salvaje, esfera normal. Si alguno de estos dos nuevos hooks se dispara, por primera vez vamos a ver el momento exacto en que el juego reconoce "la captura fue exitosa" — y lo que se vea inmediatamente después en el log (con los hooks que ya existen) debería mostrar qué pasa con el handle a continuación. Sigue siendo pura observación, cero riesgo para un Pal salvaje.

## Sesión del 2026-09-02 (continuación 9): PalCaptureSuccess se disparó en vivo — el candidato más fuerte hasta ahora

Dragón capturó otro Lamball salvaje con los dos hooks nuevos de la sesión anterior activos. Resultado, leído directo del log:

**`UPalUtility.PalCaptureSuccess` se disparó, por primera vez, justo en el momento real de la captura**, con los argumentos correctos: el jugador real como atacante, y el Lamball recién capturado como el "monstruo". Un detalle técnico importante: como esta función es nativa (confirmado en el log de UE4SS), nuestro hook se dispara DESPUÉS de que la función ya terminó de correr — así que lo que vemos es la confirmación de que ya pasó todo lo que esta función hace internamente. Justo en el mismo instante se disparó también `SpawnOtomo`, lo cual sugiere fuertemente que `PalCaptureSuccess` es la función que dispara todo el proceso de "entregar el Pal capturado al sistema de party" internamente, no solo un aviso.

**`AddOtomoHandleToFreeSlot` siguió sin dispararse, ya van tres capturas reales seguidas sin ni una sola vez** — ya no es falta de datos, es un resultado negativo consistente. Refuerza la idea de que asignar el Pal a un espacio de party es una escritura de campo nativa que ningún hook puede ver, posiblemente ocurriendo adentro de la propia `PalCaptureSuccess`.

**El otro candidato nuevo, `APalCaptureJudgeObject.OnCaptureSuccess`, nunca se disparó** — descartado como parte del flujo normal de captura con esfera; por sus funciones hermanas (`ChallengeCapture`, etc.) ahora parece ser una clase de un sistema de desafíos/arena de captura, no la captura de campo normal.

**Por qué esto importa para el objetivo real del mod**: `PalCaptureSuccess` es ahora el candidato más fuerte encontrado hasta ahora para la Pregunta 4 del diseño (una función limpia y ya existente para una captura sin esfera). Pero **todavía no es algo para probar**: solo la vimos ser llamada por el flujo real de esfera — no sabemos qué información prepara ese flujo antes de llamarla, que esta función quizás asuma que ya existe. Llamarla directamente sobre un Pal salvaje que nunca pasó por una esfera real es un riesgo distinto a todo lo probado hasta ahora, y no cumple todavía la condición de Dragón de "no probar hasta estar seguros."

**Próximo paso, sigue siendo pura observación**: un par de capturas más (variando de especie/dificultad) para confirmar que `PalCaptureSuccess` se dispara siempre, y buscar qué función LLAMA a `PalCaptureSuccess` — eso mostraría qué se prepara justo antes, y si es algo que se podría replicar para un Pal que nunca pasó por una esfera.

## Sesión del 2026-09-02 (continuación 10): idea de Dragón — las jaulas de Pals cautivos en asentamientos, un camino sin esfera que YA existe en el juego

Dragón propuso algo que el proyecto no había considerado: en asentamientos/campamentos enemigos a veces hay un Pal cautivo en una jaula pequeña, y al abrirla el Pal pasa directo a la party o a la Palbox, sin usar ninguna esfera. Si eso es real (lo es, es un mecanismo conocido del juego base), es un precedente mucho mejor para estudiar que intentar llamar `PalCaptureSuccess` a ciegas, porque el propio juego ya hace "dar este Pal específico al jugador" sin tirar ninguna esfera.

Se buscó en el volcado de cabeceras y se encontró la clase real de inmediato: `class APalCapturedCage : public AActor` (nativa, siempre cargada). Tiene exactamente la forma esperada: ya tiene un handle resuelto (`SpawnedPalHandle`) para el Pal ANTES de que el jugador interactúe (nada de física de esfera ni tirada de probabilidad de captura), funciones para abrir la puerta (`OpenDoor_ToAll`, `SetDoorOpened`), y la más importante: `CapturePal_ServerInternal(Player)` — muy probablemente la función que entrega el Pal al jugador cuando se abre la puerta.

Esta forma — un Pal que ya tiene handle, entregado con una sola llamada, sin mecánica de esfera — se parece mucho más a lo que este mod realmente quiere (un Pal salvaje que ganó suficiente confianza simplemente se une) que intentar reproducir una captura con esfera.

Se agregaron observaciones de solo lectura para toda esta clase a `OtomoWatch.lua`, ya desplegadas al juego y al mirror. Todavía sin probar en vivo.

**Próximo paso pedido a Dragón**: encontrar una jaula real en un asentamiento/campamento enemigo y abrirla de forma normal — sin esfera, solo la interacción de la puerta. Si `CapturePal_ServerInternal` se dispara limpio con un jugador y un handle válidos, y `AddOtomoHandleToFreeSlot` sigue sin dispararse ni siquiera aquí, seria una evidencia fuerte de que el paso de "unirse a la party" está escondido dentro de estas funciones de alto nivel en todos los casos, no es un paso aparte que se pueda enganchar. Sigue siendo pura observación, cero riesgo.

## Sesión del 2026-09-02 (continuación 11): CONFIRMADO EN VIVO — CapturePal_ServerInternal, el mejor resultado del proyecto hasta ahora

Dragón limpió un asentamiento (con Petallia) y abrió la celda, rescatando a un Pal cautivo (Bristla) — sin ninguna esfera. El log confirmó exactamente lo esperado: `CapturePal_ServerInternal(Player)` se disparó limpio, con el jugador real y un handle+actor ya existentes para Bristla, leído directo del campo `SpawnedPalHandle` de la jaula. Bristla se unió a la party de inmediato (segundo espacio), tal como Dragón describió.

**`AddOtomoHandleToFreeSlot` volvió a no dispararse** — van tres caminos reales distintos (cambio normal, captura con esfera, rescate de jaula) donde esta función nunca aparece para el jugador. Ya no es casualidad: lo que sea que agrega un Pal a un espacio de party está enterrado dentro de cada una de estas funciones de alto nivel, no es un paso separado que se pueda enganchar.

**Por qué es el mejor resultado hasta ahora**: `CapturePal_ServerInternal` es ahora una función real, confirmada en vivo, que toma un jugador y entrega un Pal específico — uno que YA tiene handle y actor resueltos, igual que tendría un Pal salvaje que este mod esté seguimiento — directo a la party, sin ninguna mecánica de esfera. Es una forma mucho más parecida a lo que este mod realmente necesita que `PalCaptureSuccess`. Sigue sin ser algo para llamar a ciegas — solo la vimos disparada por el flujo interno de la jaula misma — pero es el candidato más fuerte encontrado hasta ahora.

## Sesión del 2026-09-02 (continuación 12): analizando un mod descargado de Nexus — resuelve tres preguntas de diseño de una sola vez

Dragón descargó un mod de Nexus Mods ("PassiveWildPals," hace que los Pals salvajes nunca ataquen) y pidió revisar cómo está hecho. Es un .pak de Unreal que reemplaza un solo asset de Blueprint (`BP_AIAction_WildLife`) — una técnica de modding distinta a la nuestra (necesita el editor de Unreal real, no se puede reusar directamente con UE4SS/Lua) — pero leer sus cadenas de texto (sin ejecutar nada, solo texto) reveló nombres de clases y funciones nativas reales que el proyecto no conocía, confirmadas contra nuestro propio volcado del SDK:

- **`UPalAIResponsePreset`**: la tabla real de "disposición por defecto de la especie" que se buscaba desde el principio del proyecto — 8 campos (`Discover_Player/Greater/Equal/Smaller`, `Damaged_Player/Greater/Equal/Smaller`). Responde la Pregunta 1 de DESIGN.md.
- **`UPalBattleManager.TargetIsPlayerOrPlayersOtomoPal(Actor)`**, alcanzable con el ya confiable `UPalUtility.GetBattleManager(world)` — un chequeo real y ya construido de "es esto el jugador o su propio Otomo." Responde la Pregunta 2.
- **`UPalAISensorComponent`** (nativo, siempre cargado): tiene `SelectResponseBySenses` (la función real que decide cómo reacciona un Pal salvaje) y funciones de detección con una bandera real `bIgnoreOtomo` — confirma que "ignorar a los Otomo como amenaza" ya es una opción nativa del juego. Avanza la Pregunta 6. También apareció `UPalSquad` (sistema real de líder/seguidor para Pals salvajes en grupo).

Se agregaron observaciones de solo lectura para `SelectResponseBySenses` y `TargetIsPlayerOrPlayersOtomoPal` a `OtomoWatch.lua`, ya desplegadas. Todavía sin probar en vivo.

## Sesión del 2026-09-02 (continuación 13): un error real — el hook de percepción saturó el log y le bajó los FPS a Dragón

Dragón probó los dos hooks nuevos acercándose normal a un Lamball y un Chikipi. Antes de llegar a un tercero, el framerate cayó fuerte y la consola se llenó de golpe. Revisando los números: `SelectResponseBySenses` se disparó **6706 veces en aproximadamente un segundo**, en varias decenas de Pals salvajes a la vez, y cada llamada hacía una escritura de archivo completa.

**Esto fue un error de diseño real, no solo ruido.** Todos los demás hooks de este proyecto observan eventos raros (un cambio de Pal, una captura, abrir una jaula) — pasan pocas veces por minuto, así que registrar cada llamada no cuesta nada. `SelectResponseBySenses` es distinta: es parte del bucle de percepción de IA del propio juego, que corre cada tick para cada Pal salvaje cercano, haya cambiado algo o no. Tratarla igual que un evento raro convirtió "registrar cada llamada" en miles de escrituras de archivo por segundo — un costo de rendimiento real para Dragón, no solo texto de más. Debí anticipar esto por la forma misma de la función (una función de decisión por tick, no una notificación de evento) antes de pedir una prueba en vivo.

**Arreglado de inmediato**: el hook de `SelectResponseBySenses` quedó comentado (no borrado) en `OtomoWatch.lua`, ya desplegado al juego y al mirror. `TargetIsPlayerOrPlayersOtomoPal` sigue activo — no se disparó ni una vez durante esta misma prueba pesada, así que no tiene nada que ver con la caída de FPS.

**Aun así, se rescataron datos reales útiles antes de apagarlo**: `AIResponsePreset` mostró presets reales con nombre en Pals salvajes de verdad — `BP_AIResponsePreset_Escape_to_Battle_C` (monstruos comunes), `BP_AIResponsePreset_friendly_C` (tipo Lamball/Chikipi), `BP_AIResponsePreset_VillageNPC_C` (NPCs humanos) — confirma que `UPalAIResponsePreset` (Pregunta 1) es real y funciona tal como se esperaba.

**Lección para el resto de la investigación**: antes de activar un hook nuevo, preguntar "¿esto es un evento raro o una decisión de cada tick?" — los hooks de eventos (todo lo hecho hasta ahora) son seguros de registrar sin límite; los hooks por tick necesitan un límite desde el principio, no agregado después de que ya causó un problema.

## Sesión del 2026-09-02 (continuación 14): primer código real de Personality.lua

Con las Preguntas 1 y 5 de DESIGN.md ya respondidas, se reescribió `Personality.lua` de un stub a un módulo real: un ID estable de verdad por Pal (basado en `GetIndividualID().InstanceId`, un GUID real) y una lectura real de la disposición por defecto de la especie (leyendo el nombre de clase del `AIResponsePreset` del componente sensor del Pal, mapeado a curioso/huidizo/hostil).

Es el primer módulo del proyecto que hace llamadas activas de verdad (no solo observación con RegisterHook) — elegidas porque son funciones puras, sin efectos secundarios (solo convierten una referencia, no crean/destruyen/capturan nada), un riesgo mucho menor que las funciones de party/captura.

Se conectó a `Interaction.lua`, en el evento que ya existe de "acariciar/alimentar exitoso" — no se agregó ningún hook nuevo por tick, aplicando directamente la lección del incidente de FPS anterior.

**Próxima prueba real, combinada**: en la próxima sesión de juego, un acariciado/alimentado normal mostrará la disposición real de Personality.lua en el log, y acariciar/alimentar a tu propio Pal Otomo (no uno salvaje) debería disparar `TargetIsPlayerOrPlayersOtomoPal` (Pregunta 2), cerrando esa pregunta también.

## Sesión del 2026-09-02 (continuación 15): primera prueba real de Personality.lua — un bug menor arreglado, un hueco real detectado, un resultado negativo limpio

Dragón probó todo lo planeado: acarició/alimentó a Petallia, cambió a Bristla y la acarició, y encontró un Chikipi salvaje para alimentar/acariciar.

**El ID estable funcionó y es consistente** (mismo Chikipi, mismo ID en sus dos interacciones), pero con un error cosmético: algunos campos del GUID salían con el doble de dígitos hexadecimales de lo esperado por un problema de signo al convertir a texto. Arreglado con un enmascarado de 32 bits — mismo ID estable, ahora siempre con el largo correcto.

**La lectura del preset real de la especie (`AIResponsePreset`) devolvió nulo** para el Chikipi real — la disposición igual salió correcta ("curioso") pero por el valor de respaldo, no porque se haya leído el dato real. Se agregó registro detallado paso a paso para que la próxima prueba diga exactamente dónde falla esa cadena, en vez de solo "nulo".

**Resultado negativo limpio para la Pregunta 2**: `TargetIsPlayerOrPlayersOtomoPal` no se disparó ni una vez al acariciar/alimentar a dos Otomos propios (Petallia, Bristla) — descarta que ese chequeo pase por el camino de acariciar/alimentar; probablemente se usa en decisiones de combate/daño. Sigue abierta, la próxima prueba sería observarla durante una situación de combate real.

Todo esto ya desplegado. Sin problemas de rendimiento nuevos — el log reiniciado se mantuvo pequeño toda la sesión.

## Sesión del 2026-09-02 (continuación 16): la sesión de prueba más grande hasta ahora — Pregunta 2 pasa a positiva, y se confirma en vivo un ciclo completo real de ganar y perder confianza

Dragón hizo una sesión larga y variada: acarició a su propia Petallia (Alfa/Jefe) e intentó atacarla y tirarle una Pal Sphere (tanto libre como ya puesta en la base); la sacó a pelear contra varios Pals salvajes (~10 muertes); capturó una Cattiva con esfera; encontró un Lamball salvaje que huyó antes de poder interactuar; acarició/alimentó dos veces a un Sheepball (que recordaba como "Lamball" — se parecen, pero en el log solo aparece `BP_SheepBall_C`); y acarició repetidamente a una Cattiva salvaje hasta que empezó a seguirlo, y luego la atacó hasta que huyó (y, según su relato, murió después, aunque eso último no quedó en este log).

**La Pregunta 2 (`TargetIsPlayerOrPlayersOtomoPal`) ahora es POSITIVA** — se disparó repetidamente durante el combate real de Petallia contra varios Pals salvajes, con objetivos que incluyeron al jugador, a la propia Petallia, y a los Pals salvajes atacados. También se disparó justo cuando la Cattiva que perdió toda la confianza se puso hostil. Conclusión: es un chequeo real de combate/objetivo ("¿este actor cuenta como amigo para el daño/agresión?"), no parte del camino de acariciar/alimentar (donde dio negativo la vez anterior). Pregunta 2 queda sustancialmente respondida.

**Tercera confirmación en vivo de `PalCaptureSuccess`** en la captura por esfera de la Cattiva — sigue siendo 100% confiable en todas las capturas reales probadas.

**Sin datos de hook para los intentos de atacar/tirar esfera a su propia Petallia** — el juego bloquea eso antes de llegar a cualquier función que ya observamos. Es el comportamiento normal (no se puede dañar ni capturar al propio Pal), simplemente no sabemos todavía qué chequeo exacto lo bloquea. Baja prioridad.

**El resultado grande: un ciclo completo y real de ganar confianza y después perderla, observado de punta a punta, con Trust.lua, Combat.lua y Capture.lua funcionando exactamente como se diseñó.** La secuencia real con la Cattiva salvaje: 6 interacciones de acariciar reales (rank 0, puntos subiendo 0→10→20→30→40→50) → al llegar a la interacción #5, Combat.lua la marca como "siguiendo" → el jugador la golpea (daño real de 380) → Trust.lua aplica una penalización real de confianza (-25, vía un `AddFriendShip` real con valor negativo) → la confianza cae a rank 0 → deja de seguir → Capture.lua registra "perdió toda la confianza — huyendo permanentemente". Es el objetivo de diseño central del proyecto (ganar confianza, perderla, huida permanente) funcionando de verdad, con eventos reales del juego, por primera vez.

**Dos arreglos chicos en `Personality.lua`** (ya desplegados, faltan probar en vivo): se agregó una verificación `preset:IsValid()` antes de llamar a `GetFullName()` — todas las pruebas hasta ahora fallan en ese mismo paso sin ningún error explícito, lo cual coincide con un patrón conocido de UE4SS (una referencia "válida" que en realidad apunta a un objeto nulo); y se arregló que `GetOrInitState` llamaba dos veces a `GetPresetClassName` por cada Pal nuevo, duplicando cada línea de diagnóstico — ahora se llama una sola vez.

## Sesión del 2026-09-02 (continuación 17): se mapeó a fondo la estructura de clases de party/slot buscando una forma más limpia de capturar sin esfera — probablemente llegamos al techo de lo que la investigación estática puede dar

Antes de intentar el experimento arriesgado (reusar APalCapturedCage en un Pal salvaje cualquiera escribiendo su handle real en el campo SpawnedPalHandle), Dragón pidió seguir investigando primero. Se volvió a revisar CXXHeaderDump/Pal.hpp a fondo.

Se mapeó mejor toda la estructura real alrededor de la membresía de party (UPalOtomoHolderComponentBase, UPalPlayerPartyPalHolder, UPalIndividualCharacterContainer/UPalIndividualCharacterSlot) y también el sistema de captura por pesca (que usa handles de forma parecida, pero solo para una captura recién creada, no reutilizable para un Pal que ya existe). Ninguna de estas clases expone una función real de "agregar este handle a mi party" — no hay AddMember, SetHandle, ni nada parecido.

Conclusión honesta: si el paso real de "escribir este handle en el slot" es una función de C++ normal (no reflejada), nunca va a aparecer en el volcado de headers ni se puede hookear desde Lua, sin importar cuánto más se busque. La investigación estática sobre esta pregunta puntual probablemente ya llegó a su techo. Se agregaron dos observadores más de solo lectura a OtomoWatch.lua (OnUpdateSlot, FindEmptySlot) por si acaso capturan el momento indirectamente, pero el próximo paso real muy probablemente sea el experimento de escritura de campo, no más lectura.

Todo esto ya desplegado (Lua + los tres documentos). Sin cambios de comportamiento del juego todavía — sigue siendo solo observación de solo lectura.

## Sesión del 2026-09-02 (continuación 18): el experimento real de captura, implementado — tecla F11

Dragón pidió avanzar de verdad hacia terminar el mod en vez de seguir investigando sin parar. Con la investigación estática ya en su techo, se implementó el experimento real: Capture.TryDirectCapture llama directamente a la función real UPalUtility.PalCaptureSuccess(Jugador, Monstruo) sobre un Pal salvaje que nunca pasó por un lanzamiento real de esfera — la función más confiable de todo el proyecto (se disparó 100% de las veces en las tres capturas reales probadas).

Se conectó a una tecla nueva y separada, F11, en Interaction.lua — a propósito NO comparte el camino de acariciar/alimentar, y NO está conectada todavía al flujo automático de OnTrustMaxed. Es una prueba manual, un Pal, contenida.

Registra el dueño real del Pal (OwnerPlayerUId) antes y después de la llamada, y si el actor sigue siendo válido después — todo grabado en el log ANTES de que ocurra la llamada riesgosa, mismo principio de "log a prueba de crash" de Logger.lua. Es honestamente la primera llamada real experimental del proyecto (no solo cuidadosa-pero-seguro): un pcall puede atrapar un error de Lua, pero no un crash nativo del motor — ese peor caso no se puede descartar del todo desde Lua.

Ya desplegado (Lua + los tres documentos). Instrucciones detalladas de cómo probarlo la próxima vez que abra el juego se le dieron directamente a Dragón en el chat.

## Sesión del 2026-09-02 (continuación 19): CONFIRMADO EN VIVO — la captura sin esfera funciona de verdad, la pregunta 4 de DESIGN.md queda respondida

Dragón probó F11 contra tres Pals salvajes distintos en una sola sesión: un Sheepball (le decía "Lamball" de nuevo, se confunden), una Cattiva, y un Mammorest (un Pal grande, tipo jefe). Los tres se unieron a su party real. Sin esfera. Sin que el juego se cayera. Lo confirmó directamente viendo su pantalla de party.

Es el resultado más grande de todo el proyecto: UPalUtility.PalCaptureSuccess(Jugador, Monstruo) es una función real y funcional de captura sin esfera. Ya se conectó Capture.OnTrustMaxed para que la llame de verdad (antes solo dejaba un mensaje de "aquí capturaría") y también para que avise a Combat.StopFollowing una vez que el Pal ya es un miembro real de party. Esto cierra la Sección 3.5 de DESIGN.md, el último subsistema que quedaba como esqueleto en todo el proyecto.

Único detalle notado: no se ve el efecto visual de captura (la luz que aparece al liberar un Pal de una jaula) — es solo cosmético, el Pal sí queda en la party de verdad.

Ya desplegado (Lua + los tres documentos). Falta probar el camino 100% automático (acariciar un Pal salvaje hasta la interacción #5 y ver si captura solo, sin usar F11) — la próxima sesión normal de acariciar/alimentar debería activarlo por primera vez sin que Dragón haga nada especial.

## Sesión del 2026-09-02 (continuación 20): número propio en vez de perseguir la curva real, y arreglo de dos teclas que chocaban con el juego/Windows

Dragón dio dos correcciones directas y buenas: (1) no tiene sentido investigar la curva real de rango de amistad del juego para saber cuándo dispara la captura automática — nosotros controlamos el disparador, así que se puso un número propio (55 de amistad) y se puede ajustar después de confirmar que funciona; (2) F11 resultó ser pantalla completa de Palworld y F12 la tecla de captura de pantalla de Steam — ambas chocan con el juego/Windows por fuera de UE4SS. Se cambió la tecla de prueba de captura a CTRL+K (mismo patrón que usa el propio mod de atajos de UE4SS) y se eliminó la tecla F12 por completo, ya no hace falta.

Ya desplegado. Falta probar: que la captura automática dispare sola al llegar a 55 de amistad (sin usar CTRL+K).

## Sesión del 2026-09-02 (continuación 21): diagnosticado "la ganancia pasiva parece rota" — en realidad no lo está

Dragón reportó que tras 5 interacciones exitosas y varios minutos de seguimiento no veía progreso, y que la captura solo ocurría "en el 6to acariciado" — concluyendo que la ganancia pasiva no funciona o no dispara la captura. Se revisó el log línea por línea para las 3 capturas reales de esa sesión (SamuraiDog/"Pupperai", WeaselDragon jefe/"Chillet", PinkCat/Cattiva).

Conclusión confirmada con matemática exacta sobre los propios números del log: la ganancia pasiva (+2 cada ~15s) SÍ estaba funcionando sin interrupción todo el tiempo, incluso mientras Dragón interactuaba con otro Pal en otra parte del mapa. En 2 de las 3 capturas, fue literalmente el tick pasivo (no el acariciado) el que cruzó el umbral de 55 y disparó la captura — el acariciado en sí casi nunca se atrapa cruzando su propio umbral, porque el chequeo que corre justo después de acariciar lee el punto ANTES de que ese mismo acariciado realmente se aplique (llega 2-3s tarde); es el siguiente tick pasivo, hasta 15s después, el que lo atrapa. Sumado a que el mod no muestra el número de amistad en pantalla, no hay forma de que el jugador vea que sí está subiendo — de ahí la sensación de "no pasó nada".

No se cambió código esta pasada — fue un diagnóstico puro a pedido de Dragón ("mira qué encuentras en los logs"). El sistema de doble-chequeo (interacción + tick pasivo) agregado en la pasada anterior queda confirmado funcionando exactamente como se diseñó. Progreso sin cambios (73%).

## Cierre del día 1 (2026-09-02): próxima tarea es un indicador visual de confianza

Reacción de Dragón al diagnóstico de la pasada anterior (la ganancia pasiva sí funciona, solo era invisible): agregar una barrita secundaria debajo de la barra de vida del Pal salvaje, mostrando el progreso real de amistad/domesticación — sube con caricias/comida y con la ganancia pasiva por cercanía, y baja visiblemente si el Pal recibe daño. Ya quedó escrito en la sección de Fase 6 de DESIGN.md con la especificación completa y dos enfoques de UI a investigar primero (extender la barra de vida real vs. un overlay propio simple) — es lo primero para la próxima sesión, antes de seguir con balance/pulido.

Todo lo de hoy está desplegado en ambos destinos y los tres documentos están sincronizados. También para que quede constante: todo este proyecto — cada pasada, cada hook, cada entrada de este archivo — se hizo en un solo día, no en meses. Vale la pena tenerlo en cuenta la próxima sesión para las expectativas de ritmo.

## Sesión del 2026-09-03 (continuación 22, día 2): implementado el indicador visual de confianza

Se investigó primero la clase real de la barra de vida del juego (UPalUICharacterHPGaugeBase) pero se descartó reutilizarla — es una clase base nativa abstracta, el widget visual real vive en una subclase de Blueprint desconocida, y crear un widget UMG desde Lua es una categoría nueva sin confirmar. En su lugar se usó una técnica más simple y ya probada en el mundo de mods de UE4SS: enganchar el evento de dibujo por frame del HUD (AHUD:ReceiveDrawHUD, la clase real del HUD de Palworld extiende AHUD directamente) y dibujar dos rectángulos planos con AHUD:DrawRect, ubicados con AHUD:Project (mundo a pantalla).

Archivo nuevo: Indicator.lua. Lee un nuevo Trust.GetFollowingSnapshot() (usa el punto ya guardado en caché, no llama GetFriendshipPoint() de nuevo por cada Pal en cada frame — lección directa del incidente de SelectResponseBySenses de la pasada 33, que sí lo hacía y causó caída de rendimiento). Cero llamadas a Logger.log dentro del camino de cada frame (solo una vez, en el primer frame, para confirmar que el hook está activo).

Dos cosas sin confirmar todavía, dichas con honestidad: (1) se asume que Project() devuelve Z<=0 cuando el punto está detrás de la cámara — es una convención común en mods de UE4 pero no confirmada en este build específico; (2) la altura sobre el Pal (220 unidades) es un número fijo, no por especie — probablemente se vea mal en Pals muy chicos o muy grandes hasta que se ajuste después de verlo en el juego.

Ya desplegado (Lua + los tres documentos). Falta la prueba real: acariciar un Pal salvaje y ver si aparece la barra, en qué posición, y si sube/baja correctamente.

## Sesión del 2026-09-03 (continuación 23): el primer intento del indicador falló en vivo — diagnóstico limpio y arreglo con un enfoque totalmente distinto

Dragón probó la barra de confianza en un Foxparks y un Pengullet, ambos acariciados hasta seguir y capturados con normalidad — las capturas de pantalla mostraron la barra de vida real del juego funcionando bien, pero ninguna barra de PalBonds cerca, en ninguno de los dos, durante toda la sesión (~7 minutos).

Se revisó el log antes de adivinar nada: el hook se instaló sin error, pero su propia línea de confirmación de "primer frame visto" nunca apareció en todo el log, mientras el juego claramente dibujaba su HUD normal cada frame (barra de vida, brújula, misión, todo visible en las capturas). Conclusión: el HUD real de Palworld no pasa por ese evento clásico de Blueprint en absoluto — probablemente porque es un HUD moderno basado enteramente en UMG. No era un problema de posición o tamaño, era un camino completamente muerto para este juego.

Se encontró un camino distinto y más simple revisando los propios mods de ejemplo que vienen con esta instalación de UE4SS: LineTraceMod (instalado junto a PalBonds) ya usa con éxito funciones de UKismetSystemLibrary en este mismo juego. Eso llevó a UKismetSystemLibrary:DrawDebugString — una función de dibujo de texto de depuración a nivel de motor, real y nativa, que renderiza por un camino completamente distinto al HUD de Blueprint del juego, por eso no depende de lo que le faltó al primer intento.

Bonus real de diseño: el parámetro TestBaseActor está hecho exactamente para esto — se le pasa el propio Pal, y la posición del texto se vuelve un desplazamiento local que el motor reancla solo cada vez que se redibuja, sin necesitar ninguna proyección manual de mundo a pantalla.

Se reescribió Indicator.lua por completo: ahora muestra una barra de texto ("Trust 32/55 [========--------]") sobre el Pal, refrescada una vez por segundo con su propio temporizador (mismo patrón ya probado en Trust.lua). Ya desplegado. Falta la prueba real: ver si el texto aparece sobre la cabeza del Pal y si lo sigue bien mientras se mueve.

## Sesión del 2026-09-03 (continuación 24): el segundo intento del indicador también falló — causa real encontrada, y el mod que encontró Dragón marca el camino correcto

El intento con DrawDebugString tampoco mostró nada. Razonando sobre dónde corre el mod (no más lectura de logs): Palworld se distribuye como build "Shipping", y Unreal elimina las funciones DrawDebug* de ese tipo de build por diseño (quedan vacías, no dan error, simplemente no hacen nada) — coincide exactamente con lo observado. No se puede confirmar 100% desde Lua, pero es la explicación más común y documentada para este síntoma exacto en modding de Unreal. Ese enfoque nunca iba a funcionar aquí, sin importar la posición.

Dragón encontró un mod real que sí muestra texto junto a la barra de vida de un Pal salvaje (VisiblePalCaptureCounter, para una versión vieja del juego) — y a diferencia de todo lo intentado hasta ahora, no dibuja nada él mismo: escribe texto directamente en un widget hijo del propio gauge de vida real del juego (WBP_EnemyGauge.Text_WorkName), usando SetText_GDKInternal. Como es parte de la UI real y ya empaquetada del juego, no se puede eliminar como sí pasa con las funciones de debug-draw.

Se revisó qué sigue siendo real en la versión actual antes de reusar nada a ciegas, tal como pidió Dragón: SetText_GDKInternal sigue existiendo igual (en la clase base UPalTextBlockBase), pero la ruta exacta del widget viejo (WBP_PalNPCHPGauge_C) no aparece en ningún volcado de esta instalación — probablemente cambió de nombre con una versión más nueva del juego, tal como Dragón advirtió.

Se reescribió Indicator.lua como una pasada de solo investigación (sin escribir nada todavía): engancha dos funciones NATIVAS (UPalUICharacterHPGaugeBase:SetTargetCharacter/SetHPPercent) en vez de adivinar el nombre del Blueprint — esto funciona sin importar cómo se llame la subclase actual. Cada llamada registra el nombre real de la clase del widget en vivo. Registro limitado a 20 líneas por seguridad de rendimiento.

Ya desplegado. Falta una prueba enfocada: solo mirar a cualquier Pal salvaje (no hace falta acariciarlo ni capturarlo) para que se muestre su barra de vida, y revisar qué aparece en el log.

## Sesión del 2026-09-03 (continuación 25): los dos hooks tampoco dispararon — ahora se revisa si la clase siquiera se crea

Dragón probó acariciar y golpear sin querer a un Lamball salvaje (~10 minutos, con la barra de vida real bajando visiblemente) — ni SetTargetCharacter ni SetHPPercent se dispararon ni una vez. Tercer resultado seguido de "se instala sin error, nunca se dispara". Conclusión real y útil: esas dos funciones específicas no son las que realmente manejan la barra de vida de un Pal salvaje en esta versión, sean para lo que sean.

En vez de adivinar un cuarto nombre de función, se agregó un chequeo distinto: ¿la clase siquiera se crea durante el juego normal? FindAllOf(NombreDeClase) — una función real de Lua de UE4SS, de la misma familia que FindFirstOf ya usada en todo el proyecto — devuelve todos los objetos vivos de una clase. Se agregó un escaneo periódico (cada 2 segundos) buscando instancias vivas de PalUICharacterHPGaugeBase y PalUINPCHPGaugeCanvasBase, registrando cuántas hay y el nombre real de cada una si aparece alguna.

Ya desplegado. Falta una prueba más: mirar a un Pal salvaje otra vez y ver qué reporta el escaneo.

## Sesión del 2026-09-03 (continuación 26): encontrada la clase real del widget, y reutilizada una técnica propia del proyecto para ver su estructura de datos

La prueba del escaneo dio un resultado real y limpio: PalUICharacterHPGaugeBase se quedó en 0 instancias toda la sesión (confirmado que no se usa para Pals salvajes), pero PalUINPCHPGaugeCanvasBase mostró instancias vivas de una clase real y concreta: WBP_PalNPCHPGaugeCanvas_C. Esto confirma que el juego moderno reemplazó el sistema viejo (un widget por cada Pal visible) por un solo "canvas" compartido que maneja todos los Pals visibles a la vez — por eso ningún hook por-instancia disparaba nunca.

Con un objeto real y confirmado en la mano, ya no hacía falta adivinar más. Se reutilizó una técnica que este mismo proyecto ya tenía probada (dump_interesting_properties de Interaction.lua, pasada doce): recorrer las propiedades reales del widget en vivo, incluyendo las agregadas por Blueprint que un volcado estático nunca muestra. Se agregó manejo especial para propiedades tipo arreglo (largo + nombre de clase de cada elemento), ya que los "slots" de cada Pal casi seguro están guardados en un arreglo así dentro del canvas.

Se conecta para correr automáticamente, una sola vez, en cuanto el escaneo encuentra la instancia real (no la del Blueprint). Sigue siendo de solo lectura.

Ya desplegado. Falta una prueba más: mirar un par de Pals salvajes de nuevo para que el canvas esté activo y poblado, y revisar el log para ver el volcado real de campos.

## Sesión del 2026-09-03 (continuación 27): el volcado del canvas encontró un mapa que no se puede leer — se cambia de estrategia hacia el WrapBox

El volcado de la pasada 47 funcionó y confirmó campos reales del canvas: DisplayedPalGaugeMap, DisplayedBossUGaugeMap y DisplayedPlayerGaugeMap (los tres son "MapProperty", casi seguro la tabla real que conecta cada Pal con su medidor), además de dos widgets de panel UMG: Canvas_Root (un CanvasPanel) y WrapBox (un WrapBox).

El problema: la función propia del proyecto para volcar propiedades (dump_all_properties) no sabe leer MapProperty — cae directo a "(not read)". Se revisó si la herramienta de referencia incluida (ConsoleCommandsMod/dump_object.lua, el molde original de esta técnica) sabe leerlo, y tampoco: tiene su propio comentario diciendo "hace falta soportar MapProperty algún día cuando UE4SS Lua lo soporte". O sea que leer ese mapa directamente parece no estar soportado por esta build de UE4SS Lua en absoluto, no solo por el código de este proyecto.

Se cambió de estrategia hacia el campo WrapBox en su lugar: un WrapBox es un widget UMG estándar cuyo propósito es acomodar varios widgets hijos automáticamente — encaja perfecto con "un medidor por cada Pal visible". Se confirmó, revisando tanto el volcado de headers (UMG.hpp) como los stubs de Lua generados para este juego (UMG.lua), que la clase base de WrapBox (UPanelWidget) tiene funciones reales y estándar: GetChildrenCount() y GetChildAt(Index) — funciones básicas de UMG presentes en prácticamente cualquier versión de Unreal, mucho más seguras que perseguir una API de lectura de mapas que quizás ni exista aquí.

Indicator.lua ahora guarda una referencia al canvas real en cuanto se encuentra, y en cada revisión del escaneo (cada 2s) chequea cuántos hijos tiene el WrapBox. La primera vez que ese número es mayor a 0, lista todos los hijos (clase real y nombre completo de cada uno) y vuelca por completo las propiedades del primero — buscando tanto su sub-widget de texto (el equivalente moderno de lo que el mod viejo llamaba Text_WorkName, ya que SetText_GDKInternal sigue confirmado como válido pero necesita un widget real al cual llamarlo) como el campo que identifica a qué Pal específico pertenece ese medidor.

Sigue siendo de solo lectura, nada se escribe todavía. Ya desplegado. Falta una prueba más: mirar a un Pal salvaje (o varios) para que el WrapBox realmente tenga hijos, y revisar el log para ver la cantidad de hijos, la clase de cada uno, y el volcado completo del primero.

## Sesión del 2026-09-03 (continuación 28): la prueba del WrapBox no dio nada porque duró muy poco — ahora también se revisa Canvas_Root

La prueba de la pasada 48 duró apenas ~95 segundos en total (según las marcas de tiempo del log). El canvas real se encontró y se volcó igual que antes, pero el WrapBox se quedó en 0 hijos toda la sesión — no es un resultado negativo real, simplemente no hubo tiempo suficiente para que apareciera algo ahí.

Aparte del tiempo, hay una razón estructural para dudar del WrapBox de todos modos: un WrapBox acomoda todos sus hijos en una sola posición compartida (como una fila de iconos apilados) — no encaja bien con medidores que necesitan flotar cada uno sobre su propio Pal, en su propia posición de pantalla, moviéndose de forma independiente. Canvas_Root (un CanvasPanel, también confirmado como campo real en el mismo canvas) posiciona cada hijo con su propio "slot" individual con coordenadas propias — encaja mucho mejor con esa necesidad.

Se generalizó el chequeo del WrapBox para que revise ambos contenedores (WrapBox y Canvas_Root) en cada ciclo del escaneo, usando las mismas funciones reales (GetChildrenCount/GetChildAt). El que consiga hijos primero es el que se vuelca por completo.

Sigue siendo de solo lectura. Ya desplegado. Esta vez hace falta una prueba más larga de verdad: quedarse cerca de un Pal salvaje con su barra de vida realmente visible en pantalla por un buen rato (10-15+ segundos), no solo una mirada rápida de pasada.

## Sesión del 2026-09-03 (continuación 29): Canvas_Root confirmado real, pero el volcado agarró el widget equivocado — y dos mods más revisados

La prueba larga que pidió esta vez dio una señal real: el número de hijos de Canvas_Root fue subiendo (2, 11, 17, 19, 20) mientras Dragón caminaba entre varios Pals salvajes y les pegó/acarició (un ChickenPal y un SheepBall). El WrapBox nunca se movió. Esto confirma que Canvas_Root es el contenedor real que se llena con Pals — no el WrapBox.

Pero el volcado de propiedades agarró el widget equivocado: el primer hijo (índice 0) resultó ser el WrapBox mismo — un elemento fijo que ya existe desde el principio dentro de Canvas_Root, no un Pal. Los hijos reales de cada Pal aparecen después, en los índices 1 en adelante, a medida que el número sube a docenas. La lógica anterior ("volcar solo la primera vez que hay más de 0 hijos, en el índice 0") cayó justo en ese elemento fijo.

Arreglado: ahora se listan TODOS los hijos cada vez que el número cambia (no solo la primera vez), y en vez de siempre volcar el índice 0, se vuelca la primera clase nueva que NO sea un contenedor genérico conocido (WrapBox, CanvasPanel, etc.) — sea cual sea su índice. Ya desplegado. Hace falta una prueba más: quedarse cerca de varios Pals salvajes otro rato para que Canvas_Root se llene de hijos reales más allá del WrapBox fijo.

Aparte, revisé los otros dos mods que Dragón fue dejando en la carpeta:

- **"Pal Analyzer"**: resultó ser un mod tipo LogicMods (.pak compilado, no Lua) que muestra info extra (drops, aptitud de trabajo) al mirar un Pal. No tiene código fuente que se pueda leer directamente — solo confirma que ese tipo de widget flotante es posible, nada reutilizable en concreto.

- **"RemoteAccessEverything"**: también un .pak compilado, pero este SÍ dejó algo útil: reveló nombres reales y actuales de clases relacionadas con el menú radial del juego (WBP_PlayerRadialMenu, WBP_CommonRadialMenuBase, y clases nativas confirmadas en el dump de headers: UPalUIPlayerRadialMenuBase, UPalUIRadialMenuWidgetBase) además de funciones de Blueprint como RadialMenuDecide y OnRadialMenuOpened. Esto es una pista real (no probada todavía) para el problema viejo de la pregunta 2 (el "gate" de dueño en Pet/Feed) — quizás se pueda enganchar el menú radial real en vez de seguir usando la tecla propia F9/F10. Queda anotado como pendiente, no es la prioridad ahora mismo mientras seguimos con el indicador.

## Sesión del 2026-09-03 (continuación 30): el gran hallazgo — la clase del mod viejo SÍ era real, solo nunca se había volcado antes

Esta fue la prueba que estábamos esperando. Canvas_Root se llenó de contenido real (1, 6, 10, 13 hijos...) y CADA uno de esos hijos nuevos resultó ser la clase WBP_PalNPCHPGauge_C — el nombre EXACTO que usaba el mod viejo de referencia (VisiblePalCaptureCounter). Antes habíamos concluido que esa clase debía haber sido renombrada porque no aparecía en ningún volcado de headers de esta instalación — resultó que no fue renombrada nunca, simplemente esta instalación nunca la había volcado individualmente (el volcador solo genera un archivo por clase de Blueprint que ha visto cargada al menos una vez, y por lo visto ese volcado en particular nunca la vio).

Su volcado de propiedades confirmó justo lo que hacía falta:
- WBP_EnemyGauge: el sub-widget exacto donde el mod viejo escribía el texto.
- SyncId: un campo del tipo PalInstanceID (nuestro propio "identificador estable por Pal", ya confirmado en preguntas anteriores) — justo lo que hace falta para saber a cuál Pal específico pertenece cada medidor.
- De regalo: el widget también tiene soporte nativo (aunque apagado para Pals salvajes) para mostrarse según el rango/punto de amistad real — un posible atajo futuro en vez de escribir texto a mano.

Se agregó una función que ahora lee directamente el sub-widget WBP_EnemyGauge (para encontrar el nombre real y actual del campo de texto) y el SyncId (para leer su GUID real) — todo de solo lectura todavía. Ya desplegado. Falta una prueba más: acercarse a Pals salvajes otra vez para ver el nombre real del campo de texto y un GUID legible — con eso ya se podría escribir la primera línea de texto visible de verdad.

## Sesión del 2026-09-03 (continuación 31): confirmado Text_WorkName exacto del mod viejo — y el primer intento real de escritura

El volcado del sub-widget WBP_EnemyGauge confirmó Text_WorkName, exactamente en la misma ruta que usaba el mod viejo de referencia (WBP_EnemyGauge.Text_WorkName) — es un BP_PalTextBlock_C, subclase de la clase nativa que ya habíamos confirmado antes. También se confirmaron Text_Name, Text_LevelNum, Text_GuildName (otros campos de texto reales, ya usados para nombre/nivel/gremio — no libres para reusar) y ProgressBar_HP/ProgressBar_HPBack (la barra de vida real, tampoco libre).

La lectura del SyncId (el identificador único del Pal) salió mal la vez pasada — solo mostraba un identificador genérico del objeto, no el valor real. Resulta que cada uno de esos campos (InstanceId, PlayerUId) es a su vez otra estructura anidada (un GUID de cuatro números) — hacía falta un nivel más de lectura. Ya arreglado.

Y lo más importante: con Text_WorkName confirmado, se hizo el PRIMER INTENTO REAL DE ESCRITURA de todo este esfuerzo — se llama a la función que pone texto (SetText_GDKInternal) con un texto de prueba fijo ("PalBonds TEST") sobre el primer medidor que se encuentre, una sola vez. Esto es fundamentalmente más seguro que las llamadas de acciones de juego que causaron los tres crasheos reales de antes (esas eran funciones invocadas fuera de su flujo normal interno; esto es solo poner texto en un widget que ya existe y ya se está dibujando cada cuadro).

Ya desplegado. Si Dragón ve el texto "PalBonds TEST" aparecer sobre un Pal salvaje en el juego, la pregunta difícil de todo este esfuerzo (dónde va el texto de progreso) queda respondida — lo que falta después es solo conectar los números reales.

## Sesión del 2026-09-03 (continuación 32): la escritura no falló, simplemente el widget estaba oculto — forzando visibilidad

La prueba salió sin texto visible, pero el log muestra que la llamada de escritura sí se ejecutó bien, sin ningún error. Eso es justo la señal de un widget que acepta el texto pero está oculto (Visibility = Collapsed) — poner texto no lo hace aparecer si está escondido. El nombre mismo del campo (Text_WorkName, "nombre de trabajo") y sus vecinos en el mismo widget (CachedIsWork, animaciones de ícono de trabajo) sugieren que este texto normalmente solo se muestra para un Pal que está haciendo un trabajo en la base — y se esconde el resto del tiempo. Un Pal salvaje paseando no cuenta como "trabajando", así que probablemente por eso no se veía nada.

Se agregó: revisar la Visibility real del widget antes de escribir, y forzarla a "Visible" justo antes de poner el texto de nuevo. Ya desplegado. Si esto era lo único que faltaba, el texto debería aparecer esta vez; si sigue sin verse, el siguiente paso sería revisar la visibilidad del contenedor padre, no solo este widget.

Aparte, Dragón aclaró que hay dos versiones de la fruta de cariño (kinship peach) — una menor y una mejor, dando distinta cantidad de amistad. Anotado para cuando retomemos esa parte — probablemente la carpeta "AffectionFruit" encontrada es solo una de las dos versiones.

## Sesión del 2026-09-03 (continuación 33): corrección de Dragón — el objetivo real es una barra gráfica, no texto — y primer intento de crear un widget nuevo desde cero

Dragón hizo una corrección importante y justa: el escribir "PalBonds TEST" en Text_WorkName (continuaciones 31-32) solo era una prueba para confirmar que SÍ se puede escribir en un widget en vivo — nunca fue el objetivo real. La idea original de Dragón, desde el primer día, es una barra que se LLENA (como la barra de vida) debajo del medidor de salud del Pal, mostrando el progreso real de FriendshipPoint — no texto en ningún lado. Dragón también aclaró que los tres mods de referencia (VisiblePalCaptureCounter, Pal Analyzer, RemoteAccessEverything) se dieron solo para aprender CÓMO se manipulan los widgets en este juego — nunca como plantillas para copiar literalmente ni como excusa para poner texto en vez de la barra real.

Dado a elegir entre (a) poner texto ahora con la barra real después, o (b) investigar la barra real primero aunque sea terreno no probado, Dragón eligió la opción (b).

**Investigación (grep del propio volcado de cabeceras del juego, más un mod ya incluido en esta instalación de UE4SS que hace exactamente esto hoy mismo):**
- `StaticConstructObject` es una función real de Lua que UE4SS expone directamente (no algo que un mod define) — confirmado porque el mod `BPML_GenericFunctions`, que viene incluido con esta instalación, la usa hoy mismo para crear objetos nuevos.
- `AddChildToCanvas` (en un CanvasPanel) es una función real que agrega un widget nuevo como hijo y devuelve su "slot" (con funciones para posición y tamaño).
- `UProgressBar` (la clase de una barra que se llena) sigue existiendo tal cual, con `SetPercent` y `SetFillColorAndOpacity` — exactamente lo que hace falta para la barra real.

Nada de esto se había usado antes en este proyecto — todo lo hecho hasta ahora solo leía o escribía en widgets que el juego ya había creado. Esta pasada intenta, por primera vez, CREAR un widget nuevo desde cero e insertarlo en el árbol de widgets de un Pal en vivo (dentro de su panel privado `Canvas_Innner`, encontrado hace varias pasadas). Se hace con una barra de prueba bien visible (magenta, 50%) para que sea inconfundible si aparece. Cada paso queda registrado por separado en el log, para saber exactamente cuál falla si algo sale mal.

Ya desplegado. Falta la prueba en vivo — pararse cerca de un Pal salvaje y revisar si aparece una barra magenta cerca de su medidor de vida real.

## Sesión del 2026-09-03 (continuación 34): CONFIRMADO EN VIVO — se puede crear un widget nuevo desde cero, y se corrigen los dos problemas que Dragón notó

La prueba de la continuación 33 salió bien: apareció una barra magenta real sobre un Chikipi salvaje. Revisando el log, cada paso (crear el objeto, ponerle color y porcentaje, insertarlo en el árbol de widgets, posicionarlo) devolvió "OK" — ninguno falló. Esto confirma, sin ambigüedad, que SÍ se puede crear un widget nuevo en este juego y hacerlo aparecer en pantalla — era la pregunta más difícil de todo este esfuerzo de la barra de confianza, y la respuesta es que sí funciona.

Los tres problemas que notó Dragón (solo un Chikipi la tuvo, nunca se movió, no estaba bien alineada) no eran fallas del mecanismo, sino límites a propósito de esa primera versión de prueba:
1. Solo corría una vez por sesión en total (un interruptor global), así que solo el primer Pal que el escaneo encontraba (el más cercano al aparecer) recibía la barra. Arreglado: ahora cada Pal salvaje visto recibe su propia barra, no solo el primero.
2. Nunca se actualizaba — se ponía en 50% una sola vez al crearla y nunca más. Eso es esperado, esa pasada nunca prometió que se moviera.
3. La posición era un número inventado a ciegas, sin comparar contra nada real. Arreglado: ahora se lee la posición y tamaño reales de la barra de vida verdadera del Pal, y la barra nueva se coloca justo debajo de ella.

Todavía sigue siendo una barra de prueba fija (50%, color magenta a propósito, para que se note que no es el dato real todavía) — conectarla al FriendshipPoint real necesita resolver antes el problema de "a cuál Pal le corresponde este medidor" (el SyncId sigue leyendo puros ceros).

Ya desplegado. Falta la prueba en vivo con varios Pals a la vista, para confirmar que ahora todos reciben su barra, bien alineada bajo su barra de vida real.

## Sesión del 2026-09-03 (continuación 35): la barra ya sale en todos los Pals, pero mal alineada — la causa real era usar el panel equivocado, no un mal cálculo de posición

Dragón mandó una captura: ahora varios Pals tenían su barra, pero seguía saliendo corrida hacia la derecha y más ancha que la barra de vida real, no solo desalineada verticalmente. Revisando el log, el número leído era idéntico en todos los Pals (posición 64,26 tamaño 120,4) — eso en sí es correcto y normal (es el diseño fijo del propio Blueprint, igual para cada instancia). El problema real: esa pasada insertaba la barra nueva dentro de "Canvas_Innner", que era una suposición, nunca confirmada como el mismo panel donde vive la barra de vida real. Cada panel anidado tiene su propio sistema de coordenadas — aplicar los números de un panel dentro de OTRO panel produce justo este tipo de desalineación (corrida Y con otra escala), no solo un simple desfase vertical.

Dragón sugirió, por su cuenta, básicamente la idea correcta: "copiar la posición de la barra de vida y bajarla". Tenía razón en el concepto — lo que faltaba era asegurarse de que la copia caiga en el mismo espacio de coordenadas, no en un panel vecino con otra escala.

Arreglo: se encontró que cada widget tiene un campo real "Parent" que apunta al panel exacto donde ya vive. Ahora se lee el "Parent" real de la barra de vida (`ProgressBar_HP.Slot.Parent`) y la barra nueva se agrega a ESE MISMO panel, en vez de adivinar "Canvas_Innner". Al ser el mismo panel, los números de posición/tamaño de la barra real ahora sí aplican directo, sin traducción — la barra nueva queda en la misma X, corrida hacia abajo por la altura de la barra real más un pequeño espacio.

Ya desplegado. Falta la prueba en vivo para confirmar que ahora sí queda alineada bajo la barra de vida real, en varios Pals a la vez.

## Sesión del 2026-09-03 (continuación 36): Dragón confirmó la alineación -- ahora se conecta la barra al FriendshipPoint real

Dragón confirmó con capturas que la barra ya queda bien alineada bajo la barra de vida real, y pidió seguir con la siguiente parte: que la barra muestre el dato REAL de confianza, no un 50% fijo.

Para eso hacía falta resolver un problema pendiente desde hace varias pasadas: saber a cuál Pal (de los que este mod ya sigue) le corresponde un medidor específico en pantalla. El campo que se venía intentando (SyncId) seguía leyendo puros ceros. Se encontró un campo alternativo, "bindedHandle", que resulta tener funciones reales para llegar directo al Pal de verdad: una para obtener el actor real del Pal, y desde ahí, exactamente el mismo camino que este proyecto ya usa en otras partes para leer el FriendshipPoint real del juego.

Ahora cada barra, al crearse, intenta resolver ese camino completo: si funciona, se pone en el valor real de confianza de ese Pal específico (en vez de la barra de prueba fija) y se sigue actualizando cada pocos segundos para que se mueva de verdad conforme cambia la confianza (acariciando, con daño, con el tiempo). Si no logra resolverlo, se queda en el 50% de prueba como antes, y el log dice exactamente por qué falló, para poder arreglarlo si hace falta.

Ya desplegado (Indicator.lua y Trust.lua, este último solo para exponer el número 55 que ya usaba internamente, sin cambiar su comportamiento). Falta la prueba en vivo: acariciar un Pal salvaje lo suficiente y ver si su barra empieza en un valor real (no 50%) y va subiendo.

## Sesión del 2026-09-03 (continuación 37): dos fallas reales encontradas en una sola prueba de Dragón

La prueba de Dragón mostró dos problemas separados, ambos diagnosticados directo desde el log, sin adivinar.

**Falla 1 - la barra seguía atascada en 50%.** El log mostró la causa exacta: una función que se intentó llamar sobre el "handle" (bindedHandle) no existía en ese valor -- significa que ese campo no se comporta como los objetos normales que este proyecto ya sabe leer en todas partes. Se agregó una revisión de una sola vez que prueba varias formas distintas de acceder a ese valor y anota en el log cuál (si alguna) funciona -- para dejar de adivinar y ver la forma real la próxima vez que se pruebe.

**Falla 2 - los Pals nuevos, después de alejarse del punto de aparición, no tenían barra para nada.** La causa: el código que revisa la lista de Pals visibles solo volvía a recorrerla cuando el número total de Pals visibles CAMBIABA respecto a la última vez que se revisó. Si un Pal sale de rango justo cuando otro entra, el número total puede volver a ser el mismo de antes (ej. 5 -> 6 -> 5) -- y en ese caso el código se saltaba la revisión completa, dejando al Pal nuevo sin barra. Arreglado: ahora siempre se revisa la lista completa de Pals visibles, cada pocos segundos, sin importar si el número cambió o no (instalar la barra en un Pal que ya la tiene no hace nada, así que repetir el chequeo es seguro).

Ya desplegado. Falta la prueba en vivo: acariciar un Pal y ver qué dice el log sobre la forma real del "handle" esta vez, y por separado, alejarse bastante del punto de aparición para confirmar que todos los Pals nuevos en el camino sí reciben su barra.

## Sesión del 2026-09-03 (continuación 38): encontrada la causa real de "funcionó peor" -- un error grave que apagaba todo el indicador a los 50 segundos

Dragón reportó que la prueba salió peor: los Pals que aparecieron después de alejarse del punto de inicio no tuvieron barra para nada, y las pocas barras que sí aparecieron seguían atascadas en 50%. Ambas cosas tienen causa real, encontrada en el log.

**Sobre el 50% atascado**: el log confirmó que el campo "bindedHandle" simplemente no se puede leer de la forma en que se intentó -- ninguno de los métodos probados funcionó. Es una limitación real de esta versión de UE4SS con este tipo de dato específico, no un error de cómo se llamó. La solución real: en vez de leer ese campo guardado, se "engancha" directamente la función del juego que hace el enlace (BindFromHandle) para capturar el dato correcto en el momento exacto en que ocurre -- una técnica distinta, ya probada en otras partes de este proyecto, que evita el callejón sin salida.

**Sobre "funcionó peor"**: esta fue la sorpresa real. Se encontró un error grave y silencioso: el código que revisa periódicamente los medidores tenía un límite de líneas de registro (para no llenar el log) que, sin darse cuenta, terminaba APAGANDO TODA la función después de unos 50 segundos en cada sesión -- no solo el registro, sino la revisión completa, la creación de barras nuevas y la actualización de las que ya existían. Esto explica perfectamente lo que Dragón vio: un grupo de barras al principio, y después nada, sin importar cuánto caminara o acariciara Pals. Arreglado: el límite ahora solo controla cuánto se imprime en el log, nunca el trabajo real.

También se corrigió un detalle de tiempos: si el enlace del Pal ocurre un instante después de crear la barra, ahora se reintenta cada pocos segundos hasta lograrlo, en vez de rendirse para siempre en el primer intento.

Ya desplegado. Falta una prueba en vivo que cubra todo: quedarse más de un minuto (pasando el punto donde antes se apagaba), alejarse del punto de inicio para confirmar que los Pals nuevos sí reciben barra, y acariciar un Pal para ver si esta vez su barra empieza en un valor real y se mueve.

## Sesión del 2026-09-03 (continuación 39): el enganche a BindFromHandle nunca se registró -- y un error propio impidió reintentarlo

Dragón confirmó que el arreglo del apagado a los 50 segundos funcionó (los Pals nuevos lejos del punto de inicio sí recibieron barra), pero la barra seguía atascada exactamente en 50% en todos los casos. El log mostró la causa exacta: el intento de "enganchar" la función BindFromHandle falló al leer la ruta de la clase del widget -- un error de tipo específico de UE4SS ("TrivialObject value"), un tipo de objeto más limitado de lo esperado que no soporta ese método en particular.

Pero había un segundo problema, más grave, y era un error propio: el código marcaba "ya se intentó, no reintentar más" de forma incondicional, ANTES de confirmar si el enganche realmente había funcionado. Como el primer intento falló, esa sola falla bloqueó todos los futuros intentos por el resto de la sesión -- aunque esta función se ejecuta cada pocos segundos para cada medidor visible, y un intento posterior perfectamente podría haber funcionado.

**Arreglo, en dos partes**: (1) ahora solo se marca "ya funcionó" cuando el enganche realmente tiene éxito, así que un intento fallido simplemente reintenta con el siguiente medidor visto (frecuente y gratis). (2) se prueban dos rutas distintas para encontrar la función a enganchar -- la ruta completa (si se puede leer) y una alternativa usando solo el nombre corto de la clase (un método que ya se usa con éxito en otras partes de este mismo archivo), ya que UE4SS muchas veces puede encontrar una función de Blueprint solo por su nombre corto, sin necesitar la ruta completa.

Ya desplegado (Indicator.lua, con sintaxis verificada). Falta una prueba en vivo: revisar el log buscando una línea que confirme que el enganche esta vez sí se registró, y ver en el juego si la barra finalmente empieza en un valor distinto de 50% y se mueve al acariciar un Pal.

## Sesión del 2026-09-03 (continuación 40): el lag venía del propio bucle de reintentos condenado a fallar, y el nombre de clase usado siempre estuvo mal

Dragón reportó que el juego empezó a laguear fuerte con la versión anterior, y la barra seguía atascada en 50%. El log explicó ambas cosas con una sola causa raíz.

**Por qué fallaba siempre**: cada intento de "enganchar" BindFromHandle fallaba con el mismo error exacto -- "no se encontró ninguna función con ese nombre". Revisando de nuevo los archivos de referencia del juego, la razón quedó clara: BindFromHandle en realidad pertenece a una clase distinta (la clase padre), no a la clase específica del medidor de vida que se estaba usando para buscarla -- aunque el medidor hereda esa función, no es su dueño directo, y el sistema de enganche necesita el nombre de la clase dueña real, no cualquier clase que solo la herede. Por eso absolutamente ningún intento anterior podía funcionar, sin importar cuántas veces se reintentara.

**Por qué laggeaba**: el arreglo de la vez pasada (no bloquear los reintentos para siempre) era correcto en sí mismo, pero como cada intento estaba condenado a fallar, terminó llamando a la función de enganche del juego dos veces por cada medidor visible, en cada ciclo, para siempre, sin ningún límite. Esa llamada no es gratuita internamente cuando falla -- repetirla sin parar, con más Pals en pantalla, explica perfectamente el lag creciente que Dragón notó.

**Arreglo, en dos partes**: (1) ahora se prueba primero el nombre de clase correcto y fijo (ya confirmado en los archivos de referencia del juego), que no depende de leer nada del widget en vivo -- así que también evita el error anterior de lectura. (2) se puso un límite duro de intentos totales por sesión (5): si todos fallan, el código se rinde de forma permanente y lo dice claramente en el log, en vez de seguir intentando para siempre y gastando rendimiento sin ningún beneficio.

Ya desplegado (Indicator.lua, con sintaxis verificada). Falta una prueba en vivo: confirmar que el lag desapareció, revisar el log buscando una confirmación de que el enganche funcionó esta vez, y ver si la barra por fin empieza en un valor real y se mueve al acariciar un Pal.

## Sesión del 2026-09-03 (continuación 41): el nombre correcto de la clase tampoco funcionó -- probando con la ruta completa del recurso

Dragón reportó menos lag que antes (el límite de intentos sí funcionó -- el log confirma que los 5 intentos se gastaron en menos de un segundo), pero la barra seguía en 50%. El intento anterior usaba el nombre correcto y confirmado de la clase dueña de la función, pero falló exactamente igual: "no se encontró ninguna función con ese nombre". Esto es una señal real: probablemente el sistema de enganche de este juego simplemente no resuelve bien las clases de Blueprint (las hechas en el editor visual, como esta) usando solo el nombre corto -- sin importar cuál nombre se use. La forma más confiable para este tipo de clases es la ruta COMPLETA del archivo del recurso, no solo su nombre.

**Arreglo**: en vez de intentar obtener esa ruta completa desde el propio widget del medidor (que ya sabemos que falla con un error de tipo "objeto trivial"), ahora se busca la clase real por una vía distinta -- recorriendo la lista completa de clases de Blueprint cargadas en el juego (una técnica que este mismo archivo ya usa con éxito en otras partes) hasta encontrar la que coincide por nombre, y se lee su ruta completa desde ESE objeto en vez del widget. Si se encuentra, esa ruta completa se prueba primero; los intentos anteriores (nombre corto) se mantienen como respaldo.

Ya desplegado (Indicator.lua, con sintaxis verificada). Falta una prueba en vivo: revisar el log buscando si esta vez se encontró la ruta completa, si el enganche por fin funcionó, y si la barra empieza en un valor real y se mueve.

## Sesión del 2026-09-03 (continuación 42): cuatro intentos distintos de enganche fallaron -- cambiando de estrategia por completo, ya no se intenta leer el enlace interno del juego

Dragón notó que la última prueba no mostró ningún cambio real. El log lo explicó: el plan de buscar la clase correcta por otra vía tampoco encontró nada -- ni siquiera pudo intentar la ruta completa. Con este ya son CUATRO formas distintas de intentar "enganchar" la función que vincula un medidor con su Pal, y las cuatro fallaron. A estas alturas eso ya no es "una mala suposición" -- es una señal clara de que ese mecanismo de enganche por nombre simplemente no funciona de forma confiable para funciones de Blueprint en esta instalación del juego.

**Cambio de estrategia**: en vez de seguir intentando leer o interceptar el enlace interno que el juego usa (ya se probaron tres formas distintas, las tres fracasaron por razones reales y confirmadas), ahora se intenta identificar qué Pal corresponde a cada medidor comparando POSICIONES EN PANTALLA. Cada medidor ya sabe dónde está dibujado en la pantalla. Cada Pal salvaje tiene una posición real en el mundo del juego, que se puede convertir a una posición en pantalla usando una función real y confirmada del propio juego. El Pal cuya posición en pantalla quede más cerca de un medidor específico es, casi con certeza, el dueño de ese medidor.

Este paso todavía NO intenta hacer el emparejamiento real -- solo mide y registra ambos lados (la posición proyectada de cada Pal, y la posición real de cada medidor) para confirmar en el próximo log si de verdad coinciden en el mismo sistema de coordenadas, antes de escribir cualquier lógica de emparejamiento sobre una suposición sin comprobar. Esta es la misma disciplina que sí funcionó en TODOS los arreglos reales de este archivo -- medir primero, no adivinar a ciegas (que es exactamente lo que fallaba en los últimos intentos de enganche).

Ya desplegado (Indicator.lua, con sintaxis verificada). Falta una prueba en vivo: pararse cerca de uno o más Pals salvajes por un rato y revisar el log buscando las líneas de esta nueva medición para ver si las posiciones coinciden.

## Sesión del 2026-09-03 (continuación 43): SÍ se pudo abrir "Pal Analyzer" -- Dragón tenía razón, y confirmó justo la técnica que se necesitaba

Dragón cuestionó, con razón, una afirmación anterior de que el mod de referencia "Pal Analyzer" no se podía abrir. Es cierto que viene en un formato distinto a los otros mods de referencia (un mod compilado del editor visual del juego, no un script de texto plano como los demás), pero "formato distinto" no significa "imposible de leer". Se extrajo su contenido de forma totalmente segura (solo lectura) usando una herramienta estándar y de código abierto para este tipo de archivos -- no tenía ninguna protección especial, así que se abrió sin problema.

Dentro se encontraron los nombres reales de las funciones y variables que ese mod usa (el juego guarda esos nombres como texto legible incluso después de compilar). Esto confirmó dos cosas muy útiles: primero, que la forma en que este proyecto ya lee las estadísticas de un Pal (usada en Trust.lua e Interaction.lua) es exactamente la misma que usa este otro mod real y funcional -- confirmación independiente de que ese enfoque es correcto. Segundo, y más importante para lo que se está intentando ahora mismo: ese mod SÍ convierte posiciones del mundo del juego a posiciones en pantalla (la misma idea del último cambio de estrategia), pero usando una función y una forma de llamarla ligeramente distinta a la que se había adivinado -- una diferencia técnica pequeña pero importante, ahora corregida usando exactamente la forma real y comprobada que ese mod (y un ejemplo ya incluido en la instalación del juego) demuestran que funciona.

Ya desplegado (Indicator.lua, con sintaxis verificada). Falta una prueba en vivo: pararse cerca de Pals salvajes y revisar el log para confirmar si esta forma corregida de convertir posiciones sí funciona y da números que coincidan con la posición real de los medidores en pantalla.

## Sesión del 2026-09-03 (continuación 44): revisar TODOS los mods de referencia a fondo -- ahí estaba la solución real, desde antes de empezar este proyecto

Dragón pidió revisar a fondo los CUATRO mods de referencia entregados al inicio de este proyecto, sin descartar ninguno solo por venir en un formato distinto al que usamos aquí. Tres de los cuatro (Pal Analyzer, PassiveWildPals, RemoteAccessEverything) son mods compilados del editor visual del juego, empaquetados en archivos .pak -- un formato distinto a los scripts de texto que usa este proyecto, pero abrible igual con herramientas estándar de solo lectura.

**El hallazgo principal**: releer por completo el mod "VisiblePalCaptureCounter" (uno que ya se había mirado antes, pero solo parcialmente) mostró que ese mod YA enganchaba con éxito la función exacta que llevábamos varios intentos fallando en enganchar -- usando una ruta escrita de forma completamente distinta a las cuatro que se habían probado. Los intentos anteriores nunca incluían la ruta real y completa del archivo del juego donde vive esa función -- todos le faltaba una parte esencial, no era solo un pequeño error de formato. Con la ruta real y comprobada (tomada directamente de un mod que sí funciona, no adivinada), esto finalmente debería funcionar.

También se encontró que los medidores de vida se REUTILIZAN entre distintos Pals (no son permanentes, uno por Pal) -- algo que no se había considerado. Se agregó protección para eso también, así un medidor reciclado no muestre por un momento la confianza del Pal anterior.

**Hallazgos extra, para más adelante**: los otros dos mods revelaron dos sistemas reales del juego que le sirven a este proyecto en el futuro: un sistema de "seguir a un líder" que ya usan los Pals salvajes en manada (útil para cuando un Pal en proceso de vínculo deba seguir al jugador), y el sistema real de "órdenes" que se le dan a un Pal ya capturado (asistir, atacar, esperar, huir) -- útil para la misma idea. También se confirmó un sistema real de "emotes" (animaciones de expresión), relevante para la palabra "emote"/"happy" que Dragón había marcado antes para investigar más adelante. Nada de esto se ha probado en vivo todavía -- son hallazgos de lectura, no cambios de código.

Ya desplegado el arreglo del medidor de confianza (Indicator.lua, con sintaxis verificada). Falta una prueba en vivo: revisar el log para confirmar si el enganche por fin funcionó, y si la barra empieza en un valor real y se mueve al acariciar un Pal.

## Continuación 45 (2026-09-03): confirmado en vivo + estilo de la barra + investigación de "prism"

Dragón probó la barra de confianza (pass 65) en vivo: empieza en 0%, sube al acariciar, sigue subiendo pasivamente después, y avanza hacia la captura real. Confirma que el objetivo central de la Fase 6 está resuelto.

Dos pedidos nuevos, ambos atendidos sin preguntar ("just continue"):

1. **Gradiente de color de la barra (pass 66):** revisé qué expone realmente `UProgressBar` a Lua antes de diseñar nada — `CXXHeaderDump/UMG.hpp` solo declara `SetPercent`, `SetIsMarquee` y `SetFillColorAndOpacity` como funciones invocables; el estilo visual real (bordes/imágenes) vive dentro de `WidgetStyle` (`FProgressBarStyle`/`FSlateBrush`), que no es seguro de construir desde cero vía Lua. Agregué `compute_trust_bar_color(ratio)`: interpolación lineal por canal, blanco-rosado (vacío) a rojo (lleno), aplicada tanto en la creación de la barra como en cada refresco por tick.

2. **Investigación de "prism" (pass 67):** hipótesis de Dragón era que "prism" es la animación del haz de luz al capturar. `grep -rl "Prism" CXXHeaderDump/` encontró tres coincidencias reales: `BP_CapturePrism.hpp` (`ABP_CapturePrism_C`, el arma de lanzar la Palsphere en sí — campos reales `SK_Weapon_PalSphere_001`/`CaptureSphereType`), `BP_CapturePrismBullet.hpp` (`ABP_CapturePrismBullet_C`, el proyectil lanzado — campo real `CaptureTarget`, función `SpawnCaptureObject(FGuid, AActor*)`), y `Engine.hpp`'s `ConstraintLimitMaterialPrismatic` (propiedad de un constraint físico, sin relación — descartada). Conclusión de la lectura estática: "Prism" es el nombre interno/legado del arma+proyectil de la Palsphere, no un efecto de haz de luz separado — aunque `SpawnCaptureObject` sigue siendo un candidato fuerte para donde se dispara un efecto visual de captura exitosa.

Siguiendo el pedido explícito de Dragón de un "spy" real (no solo lectura estática), registré hooks read-only en las funciones del ciclo de vida de lanzamiento/impacto/captura de ambas clases (`OnThrowInternal`, `GetCaptureLevel`, `OnEndShootAnimation`, `On Throw`, `DecrementBullet`, `SpawnCaptureObject`, `OnHitToActor`, `IsDestroy`, el delegate de rebote del proyectil) — deliberadamente sin tocar las funciones per-frame (`ReceiveTick`, `UpdateRotation`, `ExecuteUbergraph`), que en este proyecto siempre terminan en spam de logs sin aportar nada. Esto aún NO está confirmado en vivo — necesita que Dragón intente una captura real con el mod corriendo para ver el orden real de disparo en el log.

Todo verificado con `luac -p` antes de desplegar, desplegado a ambos destinos (Mods folder + mirror Proyectos), y los tres docs (Indicator.lua, hook-points.md, DESIGN.md) actualizados.

## Continuación 46 (2026-09-03): segunda tanda de spies para "prism" — prueba sin esfera

Dragón propuso una prueba mejor que solo lanzar una esfera: ir a un asentamiento y liberar un Pal enjaulado (sin esfera involucrada) para ver si aparece el mismo "beam", y comparar contra una captura real con esfera. Si el mismo hook dispara en ambos casos, no puede ser `BP_CapturePrism`/`BP_CapturePrismBullet` (específicos del arma de esfera) — tiene que ser algo compartido por ambos caminos.

Antes de que Dragón hiciera la prueba, grepeé todo el header dump con un set amplio de palabras clave (`Beam|Cage|Captive|Prisoner|Slave|Rescue|JoinParty|AddParty|JoinPal|CaptureEffect|CaptureVFX|CaptureSuccess|Pillar|LightRay|SummonEffect|SpawnEffect`) en vez de adivinar. El candidato más fuerte encontrado: `ABP_ReturnPalEffect_C : AActor` — un actor real construido enteramente alrededor de un `UNiagaraComponent* Effect` más `CacheDisappearBurstEffect`/`CacheDisappearEffect` (`UNiagaraSystem*`), que mueve un Pal desde `StartLocation` hasta `ForPlayer` con el tiempo (`LerpStartPos`, `Progress`, `CurveForLerp`) — estructuralmente es exactamente "un beam/trail mostrando un Pal viajando para volverse del jugador", y nada en su forma es específico de Otomo, así que es un candidato real para disparar tanto en captura con esfera como en liberación de jaula.

Agregué hooks read-only en `OtomoWatch.lua` (archivo dedicado a instrumentación de captura/otomo, no en Indicator.lua) para:
- `ABP_ReturnPalEffect_C`: `StartReturn`, `StartReturn_ForNetwork`, `StartReturnInternal`, `LoadAndSpawnEffect`, `ReceiveBeginPlay`, `DestroySelf`.
- `ABP_PalCaptureJudgeObject_C` (subclase Blueprint del `PalCaptureJudgeObject` nativo que este archivo ya vigilaba desde el pass 28 pero nunca disparó): `OnCaptureSuccess`, `OnFailedByMP`, `OnFailedByTest`, `OnFailedFinish`, `OnSuccessFinish`, `ReceiveBeginPlay`.
- `BP_ActionUnlockCagePalLock_C` (la interacción literal de destrabar la jaula — un ancla de tiempo exacta para la acción que Dragón va a hacer).
- `BP_CaptureWire_C` (otro actor real relacionado con captura, propósito aún no confirmado — incluido por la instrucción de Dragón de no descartar nada).

Como las cuatro son clases Blueprint sin path conocido desde el header dump, reutilicé la técnica de Indicator.lua (`FindAllOf("BlueprintGeneratedClass")` + `GetPathName()`) combinada con el patrón de reintento de este archivo (`hook_with_retry`), ya que estos actores probablemente no existen en memoria hasta que algo en el mundo realmente los genera. Deliberadamente NO se enganchó ninguna función per-frame de las cuatro clases (`ReceiveTick`, `TickEffectPosition`, `ReturnOwnerMovement`, `ExecuteUbergraph`) — la lección repetida de este proyecto (`SelectResponseBySenses`, pass 33) es que eso siempre termina en spam de logs.

Todo verificado con `luac -p`, desplegado a ambos destinos, y los tres docs (OtomoWatch.lua, hook-points.md, DESIGN.md) actualizados. Aún NO confirmado en vivo — necesita que Dragón haga la prueba real (liberar Pal enjaulado, luego capturar con esfera) y comparar qué líneas `[PRISM-SPY]` disparan en cada caso.

## Continuación 47 (2026-09-03): el lag real no era de los spies — más color dorado y arreglo de fondo

Dragón probó en vivo: liberó un Dazzi enjaulado (se unió al equipo, sin esfera), capturó un Herbil solo con caricias (confirma que la captura sin esfera funciona), y capturó una Clovee con esfera normal. Feedback: el degradado blanco-rosa a rojo "no convenció" y el juego se sintió "medio lag", suponiendo que era por los spies de prism.

Revisé el log en vez de asumir. Real: los spies de prism casi no loguearon nada (3-4 líneas) y fallaron al instante — no eran la causa. La causa real, medida: 507 líneas `[DIAG-DUMP]` en una ráfaga de 8 segundos — dumps de propiedades ya completamente respondidos desde los pases 47/51/53 que se seguían re-ejecutando cada sesión, cada línea con una escritura a disco sincrónica y forzada (Logger.lua hace flush en cada línea por diseño de seguridad ante crashes). Eliminé esos dumps obsoletos (el de LiveCanvas, el de WBP_EnemyGauge/Text_WorkName con su escritura de prueba, y el dump repetido de WBP_PalNPCHPGauge_C en el escaneo de paneles) — todos dejaron un solo log corto reconociendo que ya pasaron por ahí, sin volver a volcar todo.

También até otro cabo: `FindAllOf("BlueprintGeneratedClass")` (la técnica de resolución de paths del pass 67) falló todas las veces en el test real — la tercera confirmación de que buscar la META-clase de una clase Blueprint vía FindAllOf simplemente no funciona en este build de UE4SS (ya había fallado igual con "WidgetBlueprintGeneratedClass" en el pass 62). Arreglo real: en vez de buscar la meta-clase, usar `FindAllOf(<nombre concreto de clase>)` (la misma técnica ya probada en el proyecto, ej. pass 46) para encontrar instancias vivas reales, y de ahí leer `instance:GetClass():GetPathName()` — esa llamada específica solo había fallado antes sobre un objeto de hook (Context), nunca sobre uno devuelto directamente por FindAllOf. Además, en OtomoWatch.lua el diseño anterior solo reintentaba 60 segundos al inicio de la sesión — pero estos actores (arma de esfera, su bala, el efecto de retorno, la acción de destrabar jaula) solo aparecen cuando el jugador realmente hace la acción, que puede ser minutos después. Ahora reintenta indefinidamente (sin límite de rondas, cada 10s) ya que la llamada es barata.

Cambié el color de la barra: de blanco-rosa→rojo a bronce oscuro (vacío)→dorado brillante (lleno), sigue siendo un degradado (no un solo color plano) para que siga mostrando progreso, pero con mucho más contraste.

Todo verificado con `luac -p`, desplegado a ambos destinos, docs actualizados. Aún NO confirmado en vivo — la prueba de Dragón (liberar jaula + capturar con esfera) ocurrió ANTES de este arreglo, así que ningún spy realmente llegó a dispararse esa vez. Necesita repetir la prueba con esta build.

## Continuación 48 (2026-09-03): bug real de spam en consola + oro sólido + abandono de RegisterHook para prism

Dragón hizo otra prueba (no encontró asentamiento de nivel bajo para liberar otro Pal enjaulado, quedó pendiente) — capturó un Pal con esfera normal y acarició otro para ver la barra. Feedback: el degradado dorado "se ve mejor" pero pidió quitar el degradado y dejar solo un dorado sólido plano. Además pegó un fragmento real de consola mostrando esta línea repitiéndose cada 1-2 segundos:

```
[DIAG-PRISM] found a live BP_CapturePrism_C instance but instance:GetClass():GetPathName() still failed ... attempt to call a TrivialObject value (method 'GetPathName')
```

Esto fue un bug real mío: el "arreglo" del pass 70 (probar `instance:GetClass():GetPathName()` sobre una instancia encontrada por FindAllOf, en vez del escaneo de meta-clase) chocó con el MISMO error "TrivialObject" que ya se había visto en el pass 62 sobre un objeto de hook — confirma que `:GetClass()` no funciona en este build de UE4SS sin importar cómo se obtenga la instancia. Y peor: ese log de fallo no tenía límite de repetición, así que con dos instancias vivas de `BP_CapturePrism_C` (probablemente duplicados de primera/tercera persona), spameaba la consola cada ~2 segundos sin parar — el spam real que Dragón atrapó.

Busqué en la web un path literal publicado (la misma forma en que se encontraron los de `BindFromHandle` y `BP_OtomoPalHolderComponent`) — nada encontrado para estas clases.

Conclusión: `RegisterHook` no es viable para estas clases en este build — ya son TRES técnicas distintas de reflexión de Lua confirmadas muertas para resolver el path real de una clase Blueprint (el escaneo de meta-clase con dos variantes, y `:GetClass()` sobre dos tipos distintos de objeto). Abandoné `RegisterHook` para `BP_CapturePrism_C`/`BP_CapturePrismBullet_C` (Indicator.lua) y las cuatro clases de OtomoWatch.lua, reemplazando con polling directo de existencia/campos sobre las instancias vivas que FindAllOf ya nos da — sin path, sin `:GetClass()`, solo `:IsValid()`, `GetFullName()` y lectura directa de campos (todo ya probado en el proyecto). En OtomoWatch.lua además until ahora solo tenía 60 segundos de reintento al inicio; ahora reintenta indefinidamente cada 10s ya que estos actores solo aparecen cuando el jugador realmente hace la acción, que puede ser minutos después.

Color de la barra: ahora un dorado sólido fijo (`R=1.00, G=0.84, B=0.00`), sin degradado — el progreso ya se ve por el largo del relleno.

Todo verificado con `luac -p`, desplegado a ambos destinos, docs actualizados. Aún NO confirmado en vivo para la pregunta de "prism" — esta prueba capturó con esfera pero el bug de spam y los hooks muertos significan que no se observó nada útil todavía. Falta repetir la prueba con esta build, y la comparación con liberar un Pal enjaulado sigue pendiente de encontrar un asentamiento de nivel bajo.

## Continuación 49 (2026-09-03): pedido de mover Pet/Feed al menú radial "4" — descubrimiento grande: `repak` contra el .pak real del juego

Dragón pidió mover Pet/Feed de las teclas F9/F10 al menú radial nativo del juego (tecla "4"), porque: (1) revisar solo una cosa a la vez con F9/F10 se siente lento, y (2) ya está acostumbrado a usar el menú radial para pet/feed, y F9/F10 no son teclas normales del juego.

**Descubrimiento de capacidad, no específico de este pedido pero desbloquea todo lo demás:** en vez de seguir adivinando rutas de Blueprint (ya van tres técnicas de reflexión Lua confirmadas muertas para esto), se fue directo a la fuente real: `Pal-Windows.pak`, el archivo de assets principal del juego (~40.5GB, SIN encriptar, ya en el disco de Dragón: `Pal/Content/Paks/Pal-Windows.pak`). Se descargó `repak` (la misma herramienta ya usada antes contra pak's de mods de referencia) DIRECTO en la PC de Dragón (se confirmó que su VM de `device_bash` tiene su propio acceso a internet), y con `repak list` se sacó el listado completo y real de los 185,014 archivos del juego. Grep sobre ese listado dio las rutas reales y confirmadas de TODO lo que este proyecto había estado adivinando: `BP_CapturePrism`, `BP_CapturePrismBullet`, `BP_ReturnPalEffect`, y — lo más relevante para este pedido — el sistema real del menú radial: `WBP_PlayerRadialMenu`, `WBP_PlayerRadialMenu_MenuContent`, `EPlayerRadialMenuOpenType`.

**Hallazgo del menú radial real:** se extrajeron esos archivos (`repak unpack -i <ruta> ...`, sin descomprimir el pak completo) y se leyeron sus tablas de strings compiladas (técnica `strings`, ya probada en el pase 65 con `BindFromHandle`). Nombres reales encontrados en `WBP_PlayerRadialMenu`: `OpenPlayerActionMenu`, `"Can Open Player Action Menu"` (el chequeo de elegibilidad — el espacio es literal, es el nombre real de la función), `OnDecidedPlayerActionMenu`, `"On Decided Instruction Care"`, `OnDecidedInstruction_Feed`. (Corrección hecha ANTES de desplegar: al principio se pensó que estas cuatro últimas vivían en `WBP_PlayerRadialMenu_MenuContent_C`, pero un `strings` aparte sobre ese archivo mostró que no tiene nada de Care/Feed/Otomo — son genéricas de un contenedor de UI. Las cuatro en realidad viven en el widget exterior, `WBP_PlayerRadialMenu_C`.)

**Advertencia importante encontrada en el mismo dump de strings:** todo este sistema gira en torno al Otomo ACTIVO del jugador (`GetOtomoHolderComponent`, `TryGetSpawnedOtomo`, `IsOtomoActivated`...) — no hay ningún indicio de un concepto genérico de "el Pal que estás mirando." Esto sugiere fuertemente que el menú radial real de Pet/Feed puede estar limitado al Otomo que ya tienes activo/afuera, y quizás no tenga forma alguna de apuntar a un Pal salvaje. Esa es exactamente la pregunta abierta que los nuevos hooks (solo observación, sin efectos) van a responder con datos reales de una sesión de juego.

**Lo que se hizo (Interaction.lua, pase 42 de ese archivo):** se agregaron hooks de solo observación (mismo patrón seguro ya usado en todo el proyecto — cada uno en su propio `pcall`, cero efectos secundarios) sobre las funciones reales de arriba, más `RequestSetOtomoOrder` (nativa, confirmada en el header dump — aunque se confirmó que su enum solo tiene Default/Warlike/NotCombat, o sea es un interruptor de postura de combate, NO el selector de Care/Feed como se pensaba antes). F9/F10 siguen intactas y funcionando exactamente igual — este pase solo observa, no cambia nada todavía. Verificado con `luac -p`, desplegado en las dos ubicaciones.

**Plan de prueba para la próxima sesión de Dragón** (él mismo dijo que probará "el observer y el cambio nuevo" juntos): presionar "4" cerca de su Otomo activo y elegir Care, luego Feed, de verdad por el menú vanilla — el log debe mostrar cuáles de estas funciones disparan y en qué orden. Después, intentar lo mismo mirando a un Pal SALVAJE (sin apuntar a su Otomo) para ver si algo dispara — eso confirma o descarta de una vez la hipótesis de que el sistema nativo es exclusivo de Otomos, y decide el siguiente paso real hacia poder quitar F9/F10.

## Continuación 50 (2026-09-03): resultado de la prueba real — Dragón tenía razón sobre el menú radial, y los nombres de los hooks estaban probablemente mal

Dragón corrigió algo que yo había asumido mal en la Continuación 49: el menú radial "4" NO está limitado al Otomo activo/que te sigue. Lo demostró directamente: acarició a su Lamball activo, después sacó a un Tanzee en su base para que deambulara libre, y lo acarició IGUAL apuntándole con el mismo menú radial.

**Los hooks nativos ya existentes (MENU-WATCH, desde el pase 13) lo confirman en el log real:** aparece un par real `StartTriggerInteract`+`EndTriggerInteract` con `ActionType=4`, repitiéndose, con un `TargetInteractiveObject` real: un `PalInteractableSphereComponentNative` sobre el Pal apuntado. Esto corrige una lectura anterior de este mismo proyecto (de una prueba más vieja), que había concluido que `ActionType=2/3/4` eran "llamadas periódicas de fondo sin relación." Esa lectura estaba mal, o al menos incompleta: `ActionType=4` es claramente el disparador real del radial por-Pal, controlado por hacia dónde apuntas, no por "es este mi único Otomo activo." Buena noticia para Pals salvajes: el filtro real es más probablemente un chequeo de propiedad (ownership) en algún lugar más arriba, no una restricción rígida de "debe ser el Otomo activo."

**Los 8 hooks nuevos de Blueprint (sobre `WBP_PlayerRadialMenu_C`) fallaron TODOS** con "no UFunction with the specified name was found." El formato de la ruta está confirmado correcto (mismo formato que ya funcionó para `BindFromHandle`), así que el problema probable son los NOMBRES: la técnica `strings` no puede distinguir el nombre real (FName) del nombre bonito que Unreal genera automáticamente con espacios para mostrar en el editor. Una pista fuerte encontrada en el mismo dump de strings: el nombre de pin `CallFunc_Can_Open_Player_Action_Menu_Result` — esto es exactamente lo que Unreal genera automáticamente para una llamada a una función real llamada `CanOpenPlayerActionMenu` (sin espacios), partiendo el nombre en las mayúsculas y uniendo con guion bajo. Eso es evidencia fuerte de que el nombre real NO tiene espacios.

**Arreglo de este pase (Interaction.lua):** se cambiaron los candidatos para probar primero la forma sin espacios (`CanOpenPlayerActionMenu`, `OnDecidedInstructionCare`), dejando la forma con espacios como respaldo. También se agregó un reintento acotado (hasta 8 rondas, cada 5 segundos, mismo criterio que ya se usó en `Indicator.lua`) por si el problema real es que esa clase de Blueprint todavía no está cargada en memoria cuando corre el `Init()` del mod (que corre muy temprano, al arrancar el juego) — así se cubren las dos causas posibles sin tener que adivinar cuál es. Verificado con `luac -p`, desplegado en las dos ubicaciones.

**Sigue pendiente:** una prueba en vivo nueva para ver si con los nombres corregidos los hooks por fin se registran, y si disparan realmente al usar Care/Feed por el menú — tanto en el Otomo activo, como en un Pal propio apuntado (como el Tanzee), y lo ideal sería probar con un Pal genuinamente salvaje (sin capturar) si Dragón logra apuntarle con el menú "4" también.

## Continuación 51 (2026-09-03): nueva herramienta — InputSpy.lua, para ver qué dispara cada tecla/click

Dragón preguntó: "¿se puede hacer que puedas revisar qué función o qué hook dispara cuando presiono una tecla, o cuando hago click? así podríamos encontrar más cosas si interactúo mientras estás espiando."

Se revisó primero si existe una forma nativa genérica de hacer esto (un solo hook que capture CUALQUIER tecla/click) — no existe: ni `Engine.hpp` ni `Pal.hpp` tienen una función tipo `InputKey` reflejada como evento en `APlayerController`/`UPlayerInput` (solo hay funciones de consulta como `IsInputKeyDown`). Así que no hay un solo nombre de función al que hacerle `RegisterHook` que dispare para cada tecla real.

**Lo que sí existe y se usó:** el mismo mecanismo `RegisterKeyBind` que este proyecto ya usa con éxito para F9/F10/CTRL+K, pero aplicado a TODAS las teclas válidas que este UE4SS reconoce (la lista completa, sacada directo del propio mod `Keybinds` que viene incluido con UE4SS — no adivinada). Se creó un archivo nuevo, `InputSpy.lua`, que registra ~150 teclas/botones de mouse, cada uno con un logger compartido — así cada tecla o click real que Dragón presione aparece como su propia línea en el log, justo al lado de cualquier línea `[RADIAL-WATCH]`/`[MENU-WATCH]` que dispare en ese mismo momento. No es una correlación automática perfecta (no hay forma limpia de preguntarle al motor "qué función consumió este evento" desde Lua), pero alcanza para responder la pregunta en la práctica con solo mirar el log.

**Advertencia de riesgo nueva, marcada explícitamente:** hasta ahora este proyecto solo había registrado teclas que el juego mismo NO usa (F9, F10, CTRL+K), justo para no interferir con nada. Esta es la primera vez que se registran teclas que el juego SÍ usa activamente (WASD, botones del mouse, etc). `RegisterKeyBind` se entiende que es aditivo (agrega un oyente extra, no reemplaza ni consume el evento), así que el juego debería seguir funcionando normal — pero nunca se había probado esta forma de "registrar casi todo" en este proyecto. Se le pidió a Dragón que esté atento la primera vez que lo pruebe, por si algo se siente raro (movimiento/ataque/interactuar con retraso o sin responder), y que lo desactive de inmediato (comentando el `require`/`Init()` de `InputSpy` en `main.lua`) si pasa eso. Cada callback solo escribe una línea de log — no lee ni toca nada del juego — y tiene un tope de 400 líneas.

Es una herramienta TEMPORAL de investigación, igual que `Spy.lua`/`OtomoWatch.lua` — pensada para apagarse una vez que la pregunta del menú radial quede resuelta, no para quedar en el mod final. Verificado con `luac -p`, desplegado en las dos ubicaciones.

## Continuación 52 (2026-09-03): ¡funcionó! Las 6 funciones reales del menú radial confirmadas — y un descubrimiento nuevo: hay DOS caminos distintos

Dragón hizo una prueba corta pero deliberada: abrió el menú radial varias veces, algunas con su Otomo activo, otras apuntando a su Tanzee de la base, con `InputSpy` y los hooks del menú radial corriendo al mismo tiempo. Al leer el log combinado (teclas presionadas + hooks del menú + los hooks nativos viejos de MENU-WATCH, todo en el orden real en que pasó) se pudo responder la pregunta directamente.

**Confirmado funcionando de verdad, por primera vez en este proyecto para este sistema:**
- `Can Open Player Action Menu` (el nombre real SÍ tiene el espacio — la teoría anterior de "nombre bonito generado automáticamente" estaba mal, Unreal sí permite espacios literales en el nombre real de una función de Blueprint) — dispara apenas se presiona "4".
- `CreatePlayerActionMenu` y `OpenPlayerActionMenu` — disparan justo después, siempre en ese orden exacto.
- `On Decided Instruction Care` y `OnDecidedInstruction_Feed` — disparan al hacer click en una opción, junto con `OnDecidedPlayerActionMenu(índice)` — confirmado: índice 0 = Feed, índice 1 = Care. Un tercer click dio índice 2 solo (sin Care/Feed) — probablemente Attack, Assist o Escape.

**El hallazgo real e inesperado: estas 6 funciones SOLO disparan en uno de dos casos distintos.** Cruzando los datos: (1) presionar "4" SIN apuntar a nada específico → dispara las 6 funciones de arriba, abriendo el menú sobre el Otomo activo — coincide exactamente con lo que Dragón describió. (2) presionar "4" mientras se apunta a un Pal específico (su Tanzee, confirmado porque el hook nativo viejo de MENU-WATCH mostró el par real de `ActionType=4` contra la esfera de interacción de ESE Pal) → NINGUNA de las 6 funciones disparó. Ni siquiera `Can Open Player Action Menu`. Esto significa que apuntar a un Pal específico usa un camino de código completamente distinto, que este proyecto todavía no encontró.

Esto es progreso real, no un callejón sin salida: ahora se entiende completamente el "atajo del Otomo activo," y lo que falta se redujo específicamente a "qué función dispara cuando el menú se abre con un objetivo apuntado explícitamente."

**Arreglo de este pase:** se agregaron 12 candidatos nuevos sobre la misma clase (`WBP_PlayerRadialMenu_C`), tomados de nombres que ya estaban en el dump de strings pero no se habían probado: `SelectMapObjectId`/"Select Page by Map Object" (en Palworld, "MapObject" es el término interno para cualquier objeto interactuable del mundo, Pals incluidos — la pista más fuerte), "Select Page and Index", el trío `OpenSetup`/`CloseSetup`/`SetupEvent`, `OpenMenu`/`CloseMenu`/`IsOpened`/`IsAnyMenuOpened`, y los delegados de activación de Otomo. Cada uno probado con y sin espacio. Verificado con `luac -p`, desplegado en las dos ubicaciones.

**Sigue pendiente:** una prueba más, apuntando específicamente a un Pal (dueño o, si se puede, uno salvaje de verdad) y presionando "4", para ver si alguno de los 12 candidatos nuevos dispara.

## Continuación 53 (2026-09-03): confirmado — apuntar a un Pal usa un sistema TOTALMENTE distinto, y se encontró cuál es

Con los 12 candidatos nuevos del pase anterior, la prueba de Dragón dio un resultado limpio y contundente. Cruzando `InputSpy` + `[RADIAL-WATCH]` + los hooks nativos viejos de `[MENU-WATCH]`:

**El caso "sin apuntar a nada" quedó todavía más completo:** cada "4" sin apuntar dispara `CanOpenPlayerActionMenu` → `OpenSetup` → `OpenMenu` → `CreatePlayerActionMenu` → `OpenPlayerActionMenu`, y cerrar dispara `CloseSetup` → `CloseMenu`. Un click dispara `On Decided Instruction Care`/`OnDecidedInstruction_Feed` + `OnDecidedPlayerActionMenu(índice)` — confirmado 0=Feed, 1=Care, y esta vez apareció también un índice 6 (o sea hay más de 2 opciones en esa rueda, hasta unas 7 probablemente).

**El caso "apuntando a un Pal" — CONFIRMADO como un sistema aparte:** Dragón presionó "4" apuntando a su Tanzee CINCO veces distintas (confirmado con el hook nativo de MENU-WATCH mostrando el par real contra la esfera de interacción de ESE Pal exacto). Ninguna de esas 5 veces disparó NINGUNO de los 18 hooks probados sobre `WBP_PlayerRadialMenu_C`. Esto ya no es un problema de nombre mal escrito — es la prueba de que apuntar a un Pal y presionar "4" no pasa por esa clase para nada.

**El hallazgo importante:** en vez de seguir adivinando, se volvió a buscar en el archivo real del juego, y esta vez se encontraron dos archivos nunca revisados: `WBP_PalInteractiveObjectIndicatorUI` y `WBP_PalInteractiveObjectIndicatorCanvas`. Esto responde directamente una pregunta que este proyecto tenía abierta desde el pase VEINTE ("encontrar el Blueprint que implementa GetIndicatorInfo para los Pals") — el archivo `Canvas` tiene literalmente `GetIndicatorInfo`, `CreateIndicatorUI`, `ShowIndicator(s)`, y lo más prometedor: un delegado llamado `OnUpdateTargetInteractiveObject`, que por su nombre suena exactamente a "dispara cuando cambia el objetivo al que apunta el jugador." También tiene por separado `ShowOtomoIndicator(s)` — una prueba real de que los Pals Otomo muestran un indicador adicional/distinto encima del genérico, y de que apuntar a CUALQUIER Pal (sea Otomo o no) pasa por este sistema.

**Arreglo de este pase:** se generalizó el mecanismo de reintento (para poder aplicarlo a varias clases a la vez) y se agregaron 13 candidatos nuevos sobre `Canvas` y 8 sobre `UI` (el widget de cada uno de los 4 "slots" de interacción). Verificado con `luac -p`, desplegado en las dos ubicaciones.

**Sigue pendiente:** una prueba más, apuntando a un Pal y presionando "4", para ver si alguno de estos nuevos candidatos (sobre todo `OnUpdateTargetInteractiveObject`) dispara.

## Continuación 54 (2026-09-03): Dragón encontró la tercera familia real de menús — WBP_WorkerRadialMenu

Dragón mandó capturas de pantalla (sin texto) mostrando tres archivos bajo `WorkerRadialMenu/`: `WBP_WorkerRadialMenu.uasset`, `WBP_WorkerRadialMenu_Overlay.uasset`, `WBP_WorkerRadialMenuContent.uasset` — encontrados navegando el pak él mismo. Señaló la pista clave: los Pals de base también se llaman "workers" en el juego. Eso encaja exactamente con el caso sin resolver desde la pasada setenta y seis/setenta y siete: apuntar "4" a un Pal específico (su Tanzee de base) no dispara NINGUNO de los hooks de `WBP_PlayerRadialMenu_C`.

Extraje los tres archivos con `repak` y leí sus tablas de strings. Confirmación real: `WBP_WorkerRadialMenuContent` contiene literalmente `MsgID_Pet` y `MsgID_Feed` (además de `MsgID_MoveToBox`, `MsgID_MoveToOtomo`, `MsgID_ShowStatus`), y hay un enum dedicado `EPalWorkerRadialMenuResult` — una señal de selección mucho más limpia que el índice entero crudo del menú de jugador.

Dos clases reales, mismo split interno/externo que el menú de jugador:
- `WBP_WorkerRadialMenu_Overlay_C`: `Open`, `Close`, `Construct`, `Destruct`, `DecideMenuAction`, `CancelEvent`, `Interact`, `OnSetup`, `OnSelectedEvent`, `OnSelectedMenu`, `RegisterActionBinding`, `ListenForInputAction`, `SetDisableWeaponForUI`, `OnAnyUIPushed`/`OnPushedStackableUI` (este par recibe un struct `PalHUDDispatchParameter_WorkerRadialMenu` — candidato fuerte para dónde viaja el handle del Pal objetivo).
- `WBP_WorkerRadialMenu_C`: `Construct`, `CreateContent`, `SetupContents`, `ClearSelectedIndex`, `CalculateRadialMenuArea`, `OnInitialized`, `OnClosed`, `OnSelectedMenu`/`OnSelectedMenu_Internal`, `OnDecideIndex_forBP`.

Se dejaron fuera los nombres que solo aparecían como pines `CallFunc_*_ReturnValue` (`IsDead`, `IsSameWidget`, `TryGetIndividualActor`, `GetHUDService`, `GetPalmi`, `GetParam`, `GetComponentByClass`) — son llamadas del grafo de Blueprint hacia OTRAS clases, no funciones definidas en las clases del Worker menu.

**Cambio en Interaction.lua:** dos llamadas nuevas a `make_hook_round_runner` (reutilizando la fábrica de la pasada setenta y siete) para `WORKER_MENU_CLASS` y `WORKER_MENU_OVERLAY_CLASS`, con tag `[WORKER-WATCH]`. Solo observación, cero efectos secundarios. Verificado con `luac -p`, desplegado a ambos destinos.

**Plan de prueba:** apuntar "4" a un Pal de base/worker (el Tanzee de nuevo, u otro Pal colocado) y revisar el log por líneas `[WORKER-WATCH]` — especialmente `Open`, `OnSetup`, `OnSelectedMenu`, y `OnAnyUIPushed`/`OnPushedStackableUI`.

## Continuación 55 (2026-09-03): revisé el chorro de líneas que vio Dragón y limpié candidatos ya confirmados muertos

Dragón tuvo que salir del juego temprano y reportó ver "un montón de líneas escribiéndose una tras otra rápidamente", pidiendo revisar eso y quitar lo que ya sabemos que no funciona.

**Qué pasó realmente:** la sesión duró solo 25 segundos (20:07:15–20:07:40, reloj del juego). En esa ventana el bucle de reintentos llegó a la ronda 5 en las tres clases (`RADIAL-WATCH`, `INDICATOR-WATCH`, `WORKER-WATCH`) y absolutamente TODOS los candidatos fallaron — incluyendo los seis hooks de `RADIAL-WATCH` que llevan pasadas confirmados funcionando (`Can Open Player Action Menu`, `CreatePlayerActionMenu`, etc). Eso es la prueba clave: no fue el menú de Worker fallando específicamente, fue la sesión entera terminando antes de que CUALQUIERA de estas clases de widget se cargara (probablemente todavía en el menú principal o cargando) — así que esta corrida no da evidencia nueva sobre `WBP_WorkerRadialMenu`/`_Overlay` en ningún sentido. También importante: `Logger.lua` trunca el log en cada sesión, así que los datos completos detrás de los hallazgos "confirmado funcionando" de las pasadas setenta y seis/setenta y siete ya no existen en el log crudo — solo lo que ya quedó escrito en la documentación sobrevive.

Aparte, "un montón de líneas" es también un efecto secundario inherente al método de este proyecto (probar nombres reales por ensayo): cada `RegisterHook` fallido hace que UE4SS mismo imprima un stack traceback de Lua de varias líneas en el log, encima de la línea propia de este mod (`[X-WATCH] round N: ... = FAILED`) — así que una ronda con una docena de candidatos aún sin resolver es una docena de ráfagas de ~10 líneas, todas de golpe, cada 5 segundos. Eso es esperado e inofensivo (siguen siendo hooks de solo observación, cero impacto en el juego), pero sí había limpieza real que hacer:

**Eliminados por completo (RegisterHook falló concluyentemente en las 8 rondas en una sesión donde candidatos hermanos de la MISMA clase sí tuvieron éxito — probando que la clase estaba cargada y estos nombres simplemente no existen):** `SelectMapObjectId`, `SelectPageByMapObject`, `SelectPageAndIndex`, `IsOpened` — los cuatro eran adiciones de la pasada setenta y seis a la lista de `WBP_PlayerRadialMenu_C`, confirmados como callejones sin salida por la revisión de log de la pasada setenta y siete.

**Simplificados a un solo candidato (la OTRA forma está confirmada real, así que se borró el intento que siempre fallaba en vez de seguir probándolo cada ronda):** `CanOpenPlayerActionMenu` → ahora solo prueba `"Can Open Player Action Menu"`; `OnDecidedInstructionCare` → ahora solo prueba `"On Decided Instruction Care"`.

**Dejados intactos deliberadamente:** `ChangeMode`/`DecideMenuAction` (nunca confirmados como funcionando NI confirmados como fallo real de RegisterHook — podría ser un nombre incorrecto o simplemente algo que la prueba de Dragón nunca disparó, sin forma de saberlo sin el log crudo ya perdido) y las entradas de doble candidato `OpenSetup`/`CloseSetup`/`SetupEvent`/`OpenMenu`/`CloseMenu`/`IsAnyMenuOpened` (la pasada 77 confirmó que los seis SÍ funcionan, pero no cuál de las dos formas de nombre — quitar la incorrecta a ciegas podría romper silenciosamente un hook que sí funciona). También se dejaron intactos todos los candidatos de `INDICATOR-WATCH` y `WORKER-WATCH`, ya que el fallo total de esta sesión en esas clases no es evidencia de nada — ver arriba.

Verificado con `luac -p`, desplegado a ambos destinos.

**Sigue pendiente, sin cambios:** una prueba real en vivo de `WBP_WorkerRadialMenu`/`_Overlay` — apuntar "4" a un Pal de base/worker en una sesión que sí llegue lo suficientemente lejos dentro del juego para que la clase cargue, y revisar el log por líneas `[WORKER-WATCH]`.

## Continuación 56 (2026-09-03): WBP_WorkerRadialMenu confirmado en vivo con el mapeo completo de selección, y encontré/arreglé la causa real del lag

Dragón hizo una prueba real de 7 acciones: sacó a su Tanzee, lo acarició, lo alimentó, usó "ver estado", lo agregó a su equipo, luego lo sacó del equipo y lo acarició de nuevo; después colocó a su Petallia en la base y la acarició y alimentó también. Sintió lag otra vez durante la sesión. Ambas preguntas se responden con el mismo log.

**El menú de Worker es real y está completamente conectado.** `[WORKER-WATCH]` disparó 103 veces en total, y lo clave: `OnSetup`/`OnClosed` dispararon exactamente **7 veces cada uno** — coincide perfectamente con las 7 interacciones reales del menú worker en la prueba. Son eventos limpios, uno por apertura/cierre, sin spam — seguros para usar directamente.

**Mapeo de índice de selección recuperado** cruzando `OnSelectedMenu_Internal(index)` / `OnSelectedEvent(index)` contra el orden real de juego: **(4,5) = Pet**, **(3,1) = Feed**, **(0,2) = ShowStatus ("ver estado")**, **(1,4) = AddToParty**. 5 de las 7 pulsaciones reales coincidieron exactamente con este mapeo, en orden, sin ambigüedad (Pet→Feed→ShowStatus→AddToParty→Pet). La sexta pulsación (se esperaba: acariciar a Petallia) registró el mismo índice que Feed en vez de Pet — probablemente un doble-feed o un doble clic rápido que solo registró el segundo input; no se toma como contradicción del mapeo ya que 5/7, incluyendo las dos acciones de ocurrencia única (ShowStatus, AddToParty), coincidieron perfectamente sin colisiones. Esto encaja con el conjunto `MsgID_Feed`/`MsgID_Pet`/`MsgID_ShowStatus`/`MsgID_MoveToOtomo`/`MsgID_MoveToBox` encontrado en la pasada setenta y ocho — `MoveToBox` (enviar al Palbox) es la única opción no probada, presumiblemente el índice restante por eliminación.

Esto significa que ahora se puede leer directamente el argumento de `OnSelectedMenu_Internal` para saber EXACTAMENTE qué acción eligió el jugador sobre un Pal worker — Pet, Feed, ShowStatus, AddToParty, o (presumiblemente) MoveToBox — una señal mucho más limpia que la que dio el sistema del menú de jugador.

**La causa real del lag, encontrada y arreglada.** `[INDICATOR-WATCH]` disparó **3146** veces en esta sesión de ~137 segundos — y 2375 de esas (75%) fueron un solo hook: `UpdateInteractTargetName`, disparando con `arg1=nil` cada vez (sin datos útiles). Ese volumen, a ritmo de ~17 llamadas/segundo, es claramente un refresco de texto de UI por tick, no un evento discreto — y como `Logger.log` hace una escritura a disco síncrona y forzada por cada llamada (ver el propio encabezado de `Logger.lua`), unos miles de esas en dos minutos es un costo real y perceptible. Es exactamente la misma clase de bug que el spam de `find_targeted_pal` de la novena pasada que causó una caída de framerate en su momento. **Arreglo: se eliminó `UpdateInteractTargetName` de la lista de objetivos por completo.** No se pierde funcionalidad — `OnUpdateTargetInteractiveObject` ya cubre lo mismo a un ritmo sano de ~66 disparos por sesión, y a diferencia de `UpdateInteractTargetName` sí trae un objeto objetivo real y resoluble: confirmado en vivo disparando con `PalInteractableSphereComponentNative` sobre un actor `BP_Monkey_C` real (un Pal) — prueba directa y concreta de que este hook sí ve Pals específicamente.

Todo lo demás en `WBP_PalInteractiveObjectIndicatorCanvas_C`/`_UI_C` disparó a volúmenes claramente de evento discreto en esta misma sesión y se dejó tal cual.

Verificado con `luac -p`, desplegado a ambos destinos.

**Próxima prueba:** debería sentirse notablemente menos lag ahora que se eliminó la fuente de ~2400 líneas/sesión. También vale la pena probar la opción que sería `MoveToBox` (enviar un Pal worker de vuelta al Palbox) para confirmar el índice faltante y completar el mapeo.

## Continuación 57 (2026-09-03): el primer hook REAL (ya no solo observación) sobre el menú radial original del juego

Dragón cuestionó hacer otra sesión de verificación pasiva solo para reconfirmar el arreglo del lag ("just to check if there's no lag? do i really need that? — let's continue instead"), y tiene razón: la pasada ochenta ya recuperó un mapeo confiable de índices de selección (4=Pet, 3=Feed, 0=ShowStatus, 1=AddToParty) para `WBP_WorkerRadialMenu_C:OnSelectedMenu_Internal`, así que ya había suficiente para actuar en vez de seguir solo observando.

**Qué cambió:** `OnSelectedMenu_Internal` ahora tiene su propio hook real dedicado (ya no solo una línea de log de observación) — cuando el jugador elige Pet o Feed a través de la rueda "4" real mientras apunta a un Pal, resuelve a qué Pal fue (usando un nuevo objetivo recordado, `lastAimedInteractTarget`, que se guarda desde el hook nativo ya probado seguro de `StartTriggerInteract` cada vez que dispara con `ActionType=4` — confirmado desde la pasada setenta y cuatro como "apuntando a un Pal específico") y llama a `Interaction.OnWildPalPetted(pal)` — exactamente la misma llamada que F9/F10 ya hacen para alimentar la lógica propia de confianza/conteo de interacciones de este mod. Se eliminó el log de observación redundante para la misma función (estaba duplicando cada selección ya que este nuevo hook también registra su propio disparo).

**Por qué es seguro:** no llama a ninguna función nativa riesgosa por sí mismo — sin `PlayActionByType`, sin `AddFriendShip`, sin copias de structs, nada de lo que este proyecto se haya quemado antes. Solo lee una referencia de objeto recordada (envuelta en pcall, con un respaldo `:GetOwner()` ya que `TargetInteractiveObject` a veces es el componente `PalInteractableSphereComponentNative` del Pal en vez del actor mismo) y llama a la propia `Interaction.OnWildPalPetted` de este archivo, una función ya probada de forma segura desde la pasada dieciséis.

**Por qué importa:** para un Pal PROPIO (todo lo probado en vivo hasta ahora) esto es inofensivo — igual que siempre, `OnWildPalPetted` es básicamente contabilidad sin efecto para algo ya capturado. Pero es el siguiente paso concreto hacia realmente quitar F9/F10: si este menú alguna vez se abre sobre un Pal genuinamente salvaje, sin capturar, un Pet/Feed real a través de él ahora contará directamente hacia el sistema de confianza de este mod — y la primera vez que eso pase será también la prueba en vivo de que la pregunta de propiedad se resuelve a nuestro favor, sin necesitar una sesión dedicada aparte de "solo ve a revisar".

Verificado con `luac -p`, desplegado a ambos destinos.

**Próxima prueba real, cuando surja naturalmente (sin necesidad de ir a propósito por ella):** acariciar/alimentar a un Pal propio de nuevo por la rueda de worker y revisar líneas `[WORKER-ACTION]` confirmando que el crédito se disparó; y si alguna vez se apunta "4" a un Pal salvaje y la rueda se abre, esa es la señal grande a vigilar.

## Continuación 58 (2026-09-03): INCIDENTE REAL — el hook de la pasada 81 volvió a "capturar" dos Pals que ya eran suyos. Causa raíz encontrada, arreglada, y revertido el hook

Dragón probó "4" en un Pal de base después de que la pasada ochenta y uno saliera, y reportó algo "no natural": acariciarlo "lo puso en mi equipo y el pal soltó botín". También probó "4" en un Pal salvaje (no pasó nada) y, con razón, dijo que esa fue la dirección equivocada y pidió tener cuidado de no corromper sus Pals.

**Qué pasó realmente, confirmado directo del log:** su Petallia (tipo jefe/boss, `BP_FlowerDoll_BOSS_C`, con una amistad real ya altísima de 205866) y un segundo Pal con menor amistad (`BP_SheepBall_C`, 70) recibieron una llamada real a `PalCaptureSuccess` — la MISMA función que captura de verdad a un Pal salvaje — porque `Trust.OnInteractionSucceeded` NUNCA revisaba si el Pal ya tenía dueño. El campo de dueño (GUID) cambió de un valor real a `nil` en pleno log, y el resultado visible fue exactamente el de una captura nueva de verdad: se agregó al equipo activo, y como Petallia es tipo jefe, soltó el botín de recompensa de captura.

**Este bug NO es nuevo — existe desde la pasada treinta y nueve/cuarenta y uno.** Nunca se había disparado antes porque lo único que llamaba a esa función era F9/F10, y Dragón casi nunca presiona F9/F10 sobre sus propios Pals de base ya capturados (usa la interfaz normal del juego para esos, y F9/F10 principalmente en Pals salvajes). El error de la pasada ochenta y uno no fue un bug de código en el hook nuevo en sí — resolvió correctamente el objetivo y llamó exactamente la misma función que F9/F10 ya llaman — el error fue conectar una ruta que se dispara constantemente durante el juego normal (acariciar/alimentar tus propios Pals de base) a una función que nunca fue segura para ese caso.

**Dos arreglos, en orden de importancia:**

1. **Arreglo de raíz (se queda permanentemente, protege TODAS las rutas, incluyendo F9/F10):** se agregó `Capture.IsAlreadyOwned(pal)` — lee el mismo campo `SaveParameter.OwnerPlayerUId` que este proyecto ya lee de forma segura en otros lados, y revisa sus cuatro componentes crudos (`FGuid = {A, B, C, D}`, todos `int32`, confirmado en `CoreUObject.hpp`) contra todo-cero, que es la convención propia de Unreal para "nunca asignado" en un GUID por defecto — el estado en el que vive el campo de dueño de un Pal genuinamente salvaje. **Falla hacia el lado seguro a propósito**: cualquier fallo de lectura en la cadena devuelve `true` (tratar como ya-dueño → quien llama se salta la lógica) en vez de `false` (tratar como salvaje → proceder), ya que un falso negativo solo salta silenciosamente la contabilidad de una interacción, mientras que un falso positivo es exactamente lo que causó este incidente. `Trust.OnInteractionSucceeded` ahora se sale de inmediato, antes de tocar cualquier estado, si esto da true; `maybe_trigger_capture` (alcanzable también desde el tick de ganancia pasiva) lo revisa de nuevo como segunda capa.
2. **Se revirtió el hook real de la pasada ochenta y uno a solo observación.** Aunque el arreglo de arriba ya hace imposible esta falla específica, Dragón tenía razón en que conectar automáticamente comportamiento real que cambia el estado del juego a una acción de UI que se dispara en cada interacción normal con un Pal propio merece más cuidado deliberado del que tuvo — ahora solo registra en el log (`[WORKER-WATCH] OnSelectedMenu_Internal fired — index=N`), igual que cualquier otro hook confirmado-real de este archivo, sin llamar a `Interaction.OnWildPalPetted` ni a nada más.

También confirmado como dato aparte por la misma prueba: "4" sobre un Pal genuinamente salvaje sigue sin hacer nada — la puerta de propiedad para ambos sistemas de menú radial sigue sin encontrarse.

Verificado con `luac -p` en los tres archivos modificados (`Interaction.lua`, `Trust.lua`, `Capture.lua`), desplegado a ambos destinos.

**Sobre los Pals en sí:** los efectos visibles prácticos fueron "agregado al equipo" y "un botín soltado" — consistente con que el propio comportamiento normal de captura exitosa del juego se disparó una segunda vez sobre Pals que ya eran suyos, no con ninguna corrupción de las estadísticas, especie o identidad del Pal (esos viven en campos separados que esta llamada nunca tocó). Nada observado sugiere daño permanente, pero esto no se verificó más allá de lo que muestra el log — vale la pena que Dragón confirme visualmente que ambos Pals (la Petallia y el otro) se ven y comportan con normalidad.

## Continuación 59 (2026-09-03): un camino real hacia "el menú normal, pero sobre un Pal salvaje" — sin arte propio, sin forzar nada a abrirse

Dragón cuestionó directamente la idea del menú propio: hacer arte de iconos real, animaciones de resaltado de gajos, y sonidos de menú está genuinamente fuera de lo que este proyecto puede producir bien (la barra de confianza demuestra que dibujar cosas simples en el Canvas funciona, pero eso está lejos de un menú radial pulido). También reafirmó su preferencia real: hacer que la rueda existente de "presionar 4 sin apuntar" actúe sobre el Pal salvaje al que apuntas, en vez de tu Otomo activo — y preguntó cuál es realmente más fácil.

Coincidí con su instinto, y encontré un camino concreto mucho más prometedor que las dos opciones discutidas antes (arte propio, o forzar el menú a abrirse a ciegas sobre un objetivo no soportado — la misma categoría riesgosa que causó el incidente de la pasada ochenta y dos): la rueda de "sin apuntar" debe llamar internamente a ALGUNA función para decidir "quién es mi Otomo objetivo" antes de abrirse. Encontré un candidato real y fuerte: **`TryGetSpawnedOtomo()` en `UPalOtomoHolderComponentBase`** — un getter NATIVO simple, sin argumentos (confirmado en `Pal.hpp`, no es una función solo-de-Blueprint) que devuelve el Otomo activo actual del jugador. Si el menú lee esto (o algo equivalente) para elegir su objetivo, y si los hooks de UE4SS pueden sobrescribir el valor de retorno de una función nativa, todo el pipeline de Pet/Feed ya existente y pulido podría redirigirse hacia un Pal salvaje sustituyendo solo este valor — interfaz auténtica completa, sin arte nuevo, y sin necesidad de tocar Trust/Capture para nada.

Revisé si sobrescribir un valor de retorno es siquiera posible en esta instalación de UE4SS: el mod incluido `BPML_GenericFunctions`, en su evento personalizado `ConstructPersistentObject`, usa `OutParam:set(PersistentObject)` para escribir un valor de vuelta a través de un hook — prueba real y confirmada de que el mecanismo `:set()` subyacente existe en un objeto de parámetro envuelto. Eso es para un `RegisterCustomEvent`, no un `RegisterHook` sobre una función normal, así que no confirma del todo que lo mismo funcione para el valor de retorno de un simple getter — eso todavía necesita una prueba en vivo.

**Esta pasada SOLO observa — cero cambio de comportamiento.** Se agregó un hook pre+post sobre `TryGetSpawnedOtomo`: el pre-hook registra cada llamada (confirma si esto es realmente lo que se dispara durante la rueda sin apuntar, y si alguna vez se llama durante el caso del menú worker/apuntado — si nunca se llama ahí, es más confirmación de que los dos sistemas de menú están limpiamente separados), y el post-hook registra el valor de retorno real, y luego prueba de forma segura el mecanismo de sobrescritura con un no-op genuino: lee el valor de retorno e inmediatamente llama `ReturnValue:set()` con ese MISMO valor. El comportamiento no cambia en ningún caso (se devuelve el mismo valor) — pero si ese `pcall` tiene éxito o falla nos dice, con cero riesgo, si sustituir un Pal salvaje real aquí es siquiera mecánicamente posible antes de intentarlo alguna vez en vivo.

Verificado con `luac -p`, desplegado a ambos destinos.

**Próxima prueba:** presionar "4" normalmente (cerca de tu Otomo activo, sin apuntar) un par de veces — el log debería mostrar líneas `[OTOMO-GETTER-WATCH]` confirmando la llamada, el Otomo real devuelto, y si la prueba no-op de `:set()` dice SUPPORTED o NOT SUPPORTED. Si es soportado, el siguiente paso es una única prueba en vivo, bien acotada, sustituyendo un Pal salvaje en lugar del Otomo real por una sola pulsación — si no, este camino es un callejón sin salida y vale la pena saberlo antes de invertir más tiempo en él.

## Continuación 60 (2026-09-03): leí la sesión de prueba de la pasada 83 y encontré la explicación real — y un mejor punto para redirigir

Dragón probó: tomó un Pal de su equipo como activo, lo acarició con el menú radial, se acercó a un Pal salvaje e intentó el menú radial pero siguió apuntando a su Otomo. En vez de pedirle más detalles, leí directamente el log fresco de esa sesión (21:10:10–21:12:19).

**Confirmado en el log:**

- La prueba no-op de `ReturnValue:set()` sobre `TryGetSpawnedOtomo` funcionó las 474 veces muestreadas — el mecanismo de sobrescritura sí funciona en este build. También apareció una anomalía real: durante un tramo de ~30s el valor devuelto empezó a fallar al pedir su nombre completo (cae al formato genérico `UObject: 0x...`), con una dirección distinta cada ~3 segundos — consistente con el envoltorio de UE4SS para un puntero nulo/inválido, es decir, esta función sí puede devolver "nada" mientras el Otomo está entre estados.
- **`WORKER-WATCH` agotó las 8 rondas de reintento sin registrar NINGÚN candidato de `WBP_WorkerRadialMenu_C`/`_Overlay` en toda la sesión.** Esa clase nunca se cargó en memoria — el menú radial "de apuntar" nunca se abrió ni una vez, ni sobre el Pal de equipo ni sobre el salvaje.
- Las 7 pulsaciones reales de "4" en esa sesión pasaron todas por el menú `WBP_PlayerRadialMenu_C` (el "sin apuntar"), que por diseño siempre actúa sobre lo que devuelva `TryGetSpawnedOtomo` — el Otomo.

**Qué significa esto:** el Pal salvaje no fue ignorado porque una sobrescritura fallara — nunca se intentó ninguna sobrescritura real todavía. Fue ignorado porque el ÚNICO menú que se abrió, las dos veces, fue el menú sin apuntar, que por diseño siempre apunta al Otomo sin importar hacia dónde mires. El menú de trabajador (el que sí resuelve a un Pal específico apuntado) simplemente no se activó esta sesión.

**Por qué `TryGetSpawnedOtomo` ya no es el blanco correcto para sobrescribir:** se llama ~4 veces por segundo incluso sin ningún menú abierto (474 llamadas en ~2 minutos), o sea que otros sistemas también dependen de ella (UI de indicador, IA/seguimiento, posiblemente más) — forzarla a devolver un Pal salvaje aunque sea brevemente, sin forma de limitar el cambio solo a la llamada del menú, arriesga romper lo que sea que más la lea. Es el mismo tipo de error que causó el incidente de la pasada 82: una función compartida no es un lugar seguro para meter comportamiento específico de un Pal.

**Mejor punto de redirección encontrado:** las funciones propias de decisión de acción del menú sin apuntar — `OnDecidedInstructionCare` y `OnDecidedInstruction_Feed` (ya confirmadas reales desde la pasada 76) — que solo se disparan cuando el jugador realmente elige Acariciar/Alimentar en ESE menú. Enganchar esas de verdad y llamar a las funciones `do_pet()`/`do_feed()` de este mismo mod (ya probadas seguras) sobre el Pal salvaje apuntado (usando `find_targeted_pal()` + `Capture.IsAlreadyOwned()` para confirmar que es salvaje) no necesita ningún truco sobre una función nativa compartida. Falta todavía: no sabemos cuál de `OnDecidedInstructionCare` / `OnDecidedInstruction_Feed` / `DecideMenuAction` corresponde a Acariciar y cuál a Alimentar, ni qué argumentos traen — `RADIAL-WATCH` ya registra genéricamente `self`/`arg1`/`arg2`/`arg3` de las tres, así que la próxima prueba real solo necesita que Dragón avise en el chat "elijo Acariciar ahora" / "elijo Alimentar ahora" en orden, para poder cruzar los disparos con la acción igual que la pasada 80 recuperó el mapeo de índices del menú de trabajador.

**Cambio hecho en esta pasada (solo observación, cero cambio de comportamiento):** se redujo el registro de `OTOMO-GETTER-WATCH` — ahora solo escribe una línea cuando el valor devuelto realmente cambia respecto a la llamada anterior, en vez de en cada una de las ~474 llamadas por sesión (misma prevención de lag aplicada proactivamente esta vez, antes de que se convirtiera en una queja real, como se hizo reactivamente en la pasada 80 con `UpdateInteractTargetName`). La prueba no-op de `:set()` ya cumplió su propósito y se quitó del camino por-llamada.

Verificado con `luac -p`, desplegado en ambos destinos.

**Próxima prueba real:** apuntar a un Pal salvaje (o al Otomo activo, cualquiera sirve para el mapeo), presionar "4", y decir explícitamente en el chat cuando se elige Acariciar, luego repetir y decir explícitamente cuando se elige Alimentar. Eso da los disparos de `RADIAL-WATCH` necesarios para saber qué función/patrón de argumento corresponde a cada acción — la pieza que falta antes de conectar cualquier redirección real de Acariciar/Alimentar.

## Continuación 61 (2026-09-03): el primer intento real de sustitución — acotado, limitado en el tiempo, EXPERIMENTAL

Dragón hizo la prueba que le pedí: apuntó "4" a un Pal salvaje (sin efecto visible), y luego sacó a su Otomo y lo acarició de verdad con la misma rueda. Leí el log fresco otra vez en vez de pedirle más detalles.

**Hallazgo nuevo que cambia el plan:** `OnDecidedInstructionCare` se disparó dos veces — una con `arg1=false` justo cuando `TryGetSpawnedOtomo` devolvía un objeto no resoluble/probablemente nulo (el Otomo aún no estaba afuera), y otra con `arg1=true` justo después de que `TryGetSpawnedOtomo` acababa de devolver un Otomo real y resoluble (`BP_SheepBall_C`). Eso indica fuertemente que el argumento booleano de esta función es una SALIDA ("¿se encontró un objetivo válido?"), no algo que podamos usar para redirigir — y la función en sí no recibe ninguna referencia a un Pal como parámetro. Eso descarta el plan de la pasada 84 (enganchar `OnDecidedInstructionCare`/`OnDecidedInstruction_Feed` directamente): para cuando se disparan, el objetivo ya fue resuelto en otro lado, casi seguro mediante `TryGetSpawnedOtomo` mismo.

Confirmado de paso: `OnDecidedPlayerActionMenu` se disparó con `index=1` las dos veces que hubo una selección real de "Care" — coincide con el mapeo de la pasada 76 (0=Alimentar, 1=Acariciar). También se confirmó otra vez: `WORKER-WATCH` siguió sin poder registrar la clase del menú de trabajador en toda la sesión — el menú de apuntar sigue sin abrirse nunca, ni sobre el Pal salvaje ni sobre nada más.

**Esto vuelve a poner la sustitución sobre `TryGetSpawnedOtomo` — pero esta vez acotada, no global.** Maquinaria nueva: `radialMenuActionWindowOpen`, una bandera que solo es verdadera durante la ventana breve entre el disparo confirmado de `Can Open Player Action Menu` y el disparo confirmado de `CloseMenu` (es decir, solo mientras el menú de una pulsación de "4" está realmente abierto), con un tiempo de seguridad de 1.5s por si `CloseMenu` no llega a dispararse. `make_hook_handler` ganó un parámetro opcional `onFire` para que estas dos entradas de `radialHookTargets` abran/cierren la ventana como efecto secundario de su registro de observación ya existente, sin afectar a ninguna otra entrada.

Dentro de esa ventana estrecha, y solo una vez por ventana, el hook posterior de `TryGetSpawnedOtomo` ahora: lee la ubicación/dirección de la cámara del jugador (mismo patrón que `do_test_capture`), llama a `find_targeted_pal` (el mismo sistema de apuntado por mirada que F9/F10 ya usan de forma segura, excluyendo al Otomo real de los candidatos), verifica con `Capture.IsAlreadyOwned` que el Pal apuntado sea realmente salvaje, y si es así llama a `ReturnValue:set(wildPal)` — el mismo mecanismo `:set()` ya probado como SOPORTADO en la pasada 83, esta vez con un sustituto real en vez de un no-op. Fuera de la ventana, o si no se apunta a nada salvaje, el comportamiento queda intacto.

**Nota de riesgo honesta, sin resolver hasta probarla en vivo:** esta función no recibe ningún parámetro de Pal, así que lo que sea que realmente ejecuta la animación de Acariciar/Alimentar casi seguro vuelve a leer este mismo getter en vez de recibir un valor — esa es la apuesta de esta pasada, y no está confirmado que la lógica del juego trate correctamente a un Pal salvaje sustituido. Ningún código de Trust/Capture se toca con esta sustitución, y la ventana se cierra sola en máximo 1.5s de cualquier forma, así que un resultado malo debería quedar contenido y ser visible rápido — pero esto está marcado explícitamente como EXPERIMENTAL y es el primer intento de sustitución real de este proyecto, no una prueba no-op.

Verificado con `luac -p`, desplegado en ambos destinos.

**Próxima prueba:** apuntar "4" a un Pal salvaje y elegir Acariciar (o Alimentar) en el menú que se abra, observando con atención las líneas `[RADIAL-REDIRECT]` en el log y cualquier cosa rara que le pase al Pal salvaje o al Otomo real. Avisar de inmediato si algo se ve mal — este es exactamente el tipo de prueba en vivo donde la pasada 82 mostró que puede haber efectos secundarios inesperados.

## Continuación 62 (2026-09-03): ¿existe un sistema de "seguir" nativo y real para Pals salvajes? Investigación de solo lectura

Dragón hizo dos preguntas directas: si el tick del seguidor cada 1.5s podría ser causa de lag, y — más de fondo — si la lógica de seguimiento actual ("mandar una orden de movimiento cada ~1s, y aun así a veces la ignora") es realmente lo mejor disponible, ya que él mismo reconoce que ha funcionado pero no es sólida, cerrando con "no estoy seguro de que sepas cómo [encontrar algo mejor]".

**Sobre el lag del tick:** no hay evidencia de que lo sea. El tick del seguidor corre cada 1.5s (≈0.67/seg), solo toca a los Pals que están realmente en estado de "bonding" (normalmente 0–1 a la vez), y hace una sola llamada nativa real y con propósito (`PalMoveToLocation`) — categóricamente distinto a los dos bugs de lag reales ya encontrados y arreglados en este proyecto (`UpdateInteractTargetName` a ~17/seg con argumentos inútiles, `TryGetSpawnedOtomo` a ~4/seg desde sistemas ambientales ajenos). Si hay lag real, el log lo mostraría igual que mostró esos dos casos; por ahora nada aquí luce como candidato.

**Sobre la pregunta de seguimiento — investigación real, no una suposición:** revisé el volcado de headers del propio juego (`CXXHeaderDump/Pal.hpp`) para ver cómo decide un Otomo REAL seguir al jugador. Encontré `APalAIController:GetAIActionComponent()`, que devuelve un `UPalAIActionComponent` (una subclase de `UPawnActionsComponent`, el sistema propio de Unreal para apilar "acciones" sobre un Pawn) que administra varias clases de acción compuesta. Una de ellas, `UPalAIActionOtomoDefault : public UPalAIActionCompositeBase`, expone `SetOtomoFollowAction()` junto a `SetOtomoCombatAction()`/`SetOtomoWorkAction()`/`SetOtomoBaseCampAction()`/`SetOtomoBerserker()` — claramente la capa de decisión real que usa un Otomo de verdad para elegir entre seguir/combate/trabajo/base/berserker. Eso sería un mecanismo mucho más sólido que el "empujón" periódico con `PalMoveToLocation` que usa este proyecto ahora, el cual no reemplaza la IA propia del Pal en absoluto — solo compite con lo que decida su IA salvaje (deambular/huir) entre un tick y otro, que es justo por qué a veces "ignora" el comando: nada está reemplazando realmente su toma de decisiones, solo insistiéndole.

**El problema encontrado en la misma búsqueda:** no existe ninguna clase de acción compuesta llamada "Wild" (salvaje) en todo el volcado (revisé cada clase `UPalAIAction*`). Eso deja una pregunta real sin responder: ¿el controlador de un Pal salvaje siquiera tiene activo este `UPalAIActionComponent`, o la IA salvaje corre por un camino completamente distinto (un Behavior Tree plano, sin esta capa de acción compuesta) que este sistema nunca fue pensado para tocar? Adivinar mal aquí y llamar a `SetRootComposite`/empujar un nuevo `UPalAIActionOtomoDefault` sobre un Pal salvaje a ciegas repetiría el error de la pasada 18 (`SetActiveAI(false)`, que mató silenciosamente la autodefensa de un Pal mientras el log se veía bien) — o algo peor, ya que implica construir/adjuntar objetos de IA reales del juego, no solo cambiar un booleano.

**Lo que se subió esta pasada: solo un diagnóstico de lectura, cero cambio de comportamiento.** `Combat.StartFollowing` ahora registra, una sola vez por cada inicio de seguimiento (no por tick — sin riesgo de spam), si el `AIController` del Pal salvaje que empieza a seguir tiene un `AIActionComponent` utilizable, y si es así, qué reportan `GetCurrentAIActionCategory()`/`GetCurrentAction_BP()`. No se establece, empuja ni cambia nada — esto solo busca evidencia real antes de considerar cualquier intento de verdad.

Verificado con `luac -p`, desplegado en ambos destinos.

**Próxima prueba:** hacer que un Pal salvaje empiece a seguir como de costumbre y revisar el log en busca de líneas `[FOLLOW-DIAG]`. Si dice "HAS an AIActionComponent" (SÍ tiene), el sistema de seguimiento nativo podría ser alcanzable de verdad y valdría la pena perseguirlo. Si dice "NO usable AIActionComponent" (NO tiene uno utilizable), eso confirma que los Pals salvajes corren por un camino separado y este atajo en particular es un callejón sin salida — vale la pena saberlo de cualquier forma antes de invertir más tiempo.

## Continuación 63 (2026-09-03): BUG REAL ENCONTRADO — la sustitución de la pasada 85 apuntó dos veces AL JUGADOR, no a un Pal salvaje

Mientras respondía la pregunta de Dragón sobre el lag del tick y el sistema de seguimiento, revisé el log de su sesión más reciente (la primera vez que la sustitución de la pasada 85 se disparó de verdad) — y encontró algo que la pasada 85 no vio. De 7 sustituciones reales `[RADIAL-REDIRECT]` en esa sesión, 5 eligieron correctamente a un Lamball salvaje, pero **2 sustituyeron a `BP_Player_Female_C` — el propio personaje de Dragón — en lugar del Otomo.**

**Causa raíz:** el código de la pasada 85 llamaba a `find_targeted_pal(originLoc, forward, returned)`, excluyendo solo al OTOMO ACTUAL de los candidatos — no al jugador. `find_targeted_pal` recorre `FindAllOf("PalCharacter")`, y el propio personaje del jugador aparentemente cae dentro de ese mismo filtro (a diferencia de `do_pet`/`do_feed`/`do_test_capture`, que siempre han excluido correctamente al JUGADOR, no al Otomo, en esta misma función). Además, `Capture.IsAlreadyOwned` — consultada por primera vez sobre un actor jugador — leyó un GUID de dueño en cero desde algún componente compartido y concluyó erróneamente "es salvaje", dejando pasar la sustitución las dos veces.

**Qué pasó realmente en el juego — confirmado inofensivo, pero por suerte, no por diseño:** las dos veces, Dragón eligió "Cuidar" (Acariciar) justo después de la sustitución, y las dos veces el `AddFriendShip` real que siguió unos segundos después cayó sobre el parámetro del Otomo REAL, no el del jugador. Eso significa que lo que sea que realmente ejecuta la animación de acariciar y otorga la amistad NO vuelve a leer `TryGetSpawnedOtomo` — debe guardar el objetivo antes en la secuencia de apertura, o leerlo de otro lado por completo. Esto también responde la pregunta abierta de la pasada 85 ("¿la lógica real de Acariciar/Alimentar vuelve a leer este getter?") — aparentemente no, al menos no en el camino de código que aplica la interacción de verdad. Nada indica que le haya pasado algo al personaje de Dragón. Pero esto fue un accidente de la implementación, no una garantía, y es exactamente el tipo de hueco que ya nos costó caro en la pasada 82 (la falta de verificación de dueño) — vale la pena arreglarlo de inmediato aunque esta vez no haya pasado nada malo.

**Arreglo aplicado en la fuente:** `find_targeted_pal` ahora se llama excluyendo al JUGADOR (`player`, no `returned`) — exactamente la misma exclusión que `do_pet`/`do_feed` siempre han usado de forma segura para esta misma función. Se agregaron dos verificaciones extra como refuerzo: omitir si el `GetFullName()` del candidato encontrado coincide con el del jugador (por si la exclusión por nombre alguna vez falla), y omitir (como un no-op inofensivo, no un error) si el candidato encontrado ya es el Otomo actual.

Verificado con `luac -p`, desplegado de inmediato en ambos destinos.

**También confirmado en el mismo log, sin relación con el bug:** el tick del seguidor (~0.67/seg, solo toca Pals que están activamente en bonding) no muestra ninguna señal de ser fuente de lag — nada parecido a los dos bugs de lag reales ya arreglados antes. `WORKER-WATCH` sigue mostrando cero disparos reales en esta sesión (las 218 líneas fueron todas intentos de registro, la mayoría fallidos) — el menú de trabajador basado en apuntar sigue sin abrirse ni una vez en ninguna sesión registrada hasta ahora.

## Continuación 64 (2026-09-03): CAUSA RAÍZ ENCONTRADA para el menú de trabajador con Pals salvajes — y primer intento real de arreglo

Entre la continuación 63 y esta, en una sesión de investigación larga, Dragón volcó en vivo (Live View, "Dump as JSON") el objeto real `PalHUDDispatchParameter_WorkerRadialMenu` — una vez apuntando "4" a su Otomo real, otra vez apuntando a un Pal salvaje. Comparar los dos JSON dio la respuesta directa a "por qué el menú de trabajador (el de apuntar de verdad, distinto del menú sin apuntar) no hace nada con un Pal salvaje":

```
dueño:    IndividualHandle = PalIndividualCharacterHandle_2147480691
          OnClose          = (BP_Kitsunebi_C_2147425992.OnSelectedOrderWorkerRadialMenu)
salvaje:  IndividualHandle = PalIndividualCharacterHandle_2147480691   <- MISMO objeto
          OnClose          = ()                                       <- vacío
```

Dos problemas, no uno: (1) `OnClose` (un delegado simple, no una lista multicast — el formato "(Objeto.Función)" lo confirma) nunca se conecta a nada para el caso salvaje, así que elegir una opción del menú no tiene ninguna función de cierre que ejecutar; (2) `IndividualHandle` es el MISMO objeto exacto en ambos volcados — nunca se actualiza para apuntar al Pal que realmente se está mirando.

Verificación de que el arreglo es viable de verdad (no una suposición): `OnSelectedOrderWorkerRadialMenu` está declarada en `APalMonsterCharacter`, la clase base de TODOS los Pals del juego, salvajes o no — la función que necesitamos ya existe, sin modificar, en cualquier Pal salvaje.

**Arreglo implementado esta pasada:** un nuevo `RegisterHook` sobre `/Script/Pal.PalHUDInGame:PushWidgetStackableUI` (+ `PalHUDService:Push`, mismo patrón), el momento exacto en que el objeto `Parameter` ya construido se entrega para abrir el widget — con cada campo ya puesto pero antes de que nadie los lea. El hook no hace nada a menos que la clase del Parameter contenga "WorkerRadialMenu" (cualquier otra UI del juego queda intacta). Cuando sí es el menú de trabajador, y `find_targeted_pal` + `Capture.IsAlreadyOwned` confirman un Pal salvaje apuntado, reescribe los dos campos rotos: `Parameter.IndividualHandle` (lectura directa de `CharacterParameterComponent.IndividualHandle`, nuevo helper `get_individual_handle()`) y `Parameter.OnClose:Bind(pal_salvaje, "OnSelectedOrderWorkerRadialMenu")`.

**Lo único sin confirmar todavía:** la sintaxis exacta de UE4SS para conectar (bind) una propiedad de tipo delegado — se usó `:Bind(Objeto, "NombreFunción")` como la mejor suposición con evidencia, mensaje envuelto en su propio `pcall` y registrado por separado en el log (`[WORKER-BIND-FIX]`) para que una prueba en vivo diga de inmediato si funcionó o dé el error exacto para seguir iterando. El caso de Pals ya propios queda completamente intacto — el filtro de "solo salvajes" hace que este hook no toque nada a menos que se confirme un Pal salvaje apuntado.

Verificado con `luac -p`, desplegado en ambos destinos.

**Próxima prueba real:** apuntar el menú de trabajador real (la rueda de apuntar, no la de sin apuntar) a un Pal salvaje y elegir Acariciar o Alimentar. Revisar el log por líneas `[WORKER-BIND-FIX]`: si dice `ok` en la escritura de `IndividualHandle` y en `OnClose:Bind()`, el siguiente paso es ver si elegir Acariciar/Alimentar ahora hace algo visible de verdad sobre el Pal salvaje — reportar exactamente qué pasa (o no pasa).


## Continuación 65 (2026-09-03): tres pruebas reales, un giro real de rumbo — y dónde nos quedamos para mañana

Sesión larga de pruebas reales con Dragón, resumida:

1. **Primer intento de arreglo (continuación 64) probado en vivo: cero disparos.** Tres sesiones reales (incluida una con el suelo despejado, apuntado directo, muchos intentos) mostraron que el menú de trabajador real simplemente nunca se abría — cada "4" abría el menú sin apuntar (el que actúa sobre el Otomo activo). El arreglo de `OnClose`/`IndividualHandle` nunca tuvo oportunidad de ejecutarse.

2. **Diagnóstico añadido → se encontró que el punto de enganche estaba mal.** En una prueba donde Dragón presionó "4" varias veces apuntando a distintas cosas, el menú de trabajador SÍ llegó a abrirse de verdad (secuencia completa confirmada en el log: Construct→OnSetup→...→selección real de Acariciar→cierre). Pero el hook (`PushWidgetStackableUI`/`PalHUDService:Push`) no se disparó ni una vez cerca de ese momento — quedó probado que esas dos funciones NO son las que reparten el `Parameter` de este menú, a pesar de que la documentación del SDK decía que sí. Se encontró que `OnSetup` se dispara sin ningún argumento útil, así que el `Parameter` probablemente vive como una variable simple (`self.Parameter`) en el propio widget. Se agregó un nuevo hook real sobre `OnSetup` que lee esa variable directamente — el primer punto de enganche realmente comprobado que se dispara en una apertura real del menú.

3. **El giro real: Dragón aportó la pieza que faltaba.** Aviso directo desde el juego: *"no puedo elegir qué menú abrir, solo presiono 4, el menú que se abre depende de a qué apunto — si es un pal de base abre el menú de trabajador, si no, abre el otro."* Esto cambia todo: el menú de trabajador NO depende de si el Pal es salvaje o propio — depende de si está asignado como trabajador de una base. Un Pal salvaje NUNCA puede cumplir esa condición, sin importar qué tan bien se arregle `OnClose`/`IndividualHandle`, porque el juego decide qué menú construir ANTES de que corra cualquiera de nuestros hooks.

**Dónde nos quedamos, listo para retomar mañana:** se encontró un candidato real y concreto para esa condición de elegibilidad — `UPalCharacterParameterComponent.WorkAssignId` (un campo plano) y su función `GetWorkAssign()` — el mismo componente que este mod ya lee de forma segura para otras cosas. Se agregó SOLO un diagnóstico de lectura (`[WORKASSIGN-DIAG]`), sin tocar nada todavía, que registra este dato cada vez que se presiona "4". **Prueba pendiente para la próxima sesión:** presionar "4" apuntando a un Pal que de verdad esté asignado como trabajador en una base (debe abrir el menú de trabajador) y por separado a un Pal salvaje (abre el otro menú), y revisar el log para comparar los valores de `WorkAssignId`/`GetWorkAssign()` entre ambos casos. Si el trabajador de base muestra datos reales y el salvaje los muestra vacíos, eso confirma la teoría y el siguiente paso es encontrar una forma SEGURA de hacer que la comprobación de elegibilidad vea a un Pal salvaje como válido, sin tocar su estado real de asignación de trabajo (que podría romper la gestión de base de verdad si se hace mal).

Verificado con `luac -p` en cada cambio, desplegado en ambos destinos (carpeta del juego + espejo en Proyectos) después de cada pasada. Todo el código, DESIGN.md, hook-points.md y este archivo están al día a fecha de esta sesión.


## Continuación 66 (2026-09-03): dos frentes en paralelo — personalidad por individuo (asignación) implementada, e investigación real del mod pacifista

Dragón pidió trabajar en 2 frentes a la vez para no quedar bloqueados esperando una sola prueba. Frente 1 (menú de trabajador) sigue esperando la prueba pendiente de la continuación 65. Este bloque cubre el Frente 2, nuevo esta sesión.

**Especificación exacta de Dragón:** cada Pal salvaje individual (sin importar su especie) debe recibir uno de 4 "niveles de personalidad" al azar, con estos pesos: 50% normal (el comportamiento de su especie de siempre), 25% curioso, 10% hostil (atacará al jugador), 15% miedoso (huirá). Esto permite encontrar Pals amigables incluso en especies normalmente hostiles, y viceversa.

**Parte A — ASIGNACIÓN (implementada y desplegada esta pasada):** `Personality.lua` ya guardaba un estado por individuo (`PersonalityState[palId]`, con `palId` un ID real y estable leído de `GetIndividualHandle():GetIndividualID()`, no algo inventado). Se agregó una tabla de pesos (`PERSONALITY_TIERS`) y una función `roll_personality_tier()` que hace la tirada ponderada exacta 50/25/10/15. La tirada ocurre UNA sola vez por individuo nuevo, dentro de `GetOrInitState` (el mismo lugar donde ya se leía el comportamiento por especie), y el resultado se guarda junto con el resto del estado de ese Pal. Si el resultado es "normal", el Pal simplemente conserva el comportamiento de su especie de siempre (sin cambios); si es curioso/hostil/miedoso, ese nivel reemplaza el comportamiento efectivo. Como todo el resto del mod ya lee la disposición de un Pal a través de `Personality.GetDisposition(palId)`, ningún otro archivo tuvo que cambiar — heredan el nuevo comportamiento automáticamente. Se agregó un log `[PERSONALITY-ROLL]` por cada individuo nuevo (tier tirado, valor de especie, disposición efectiva) para poder confirmar en vivo que la distribución se ve razonable.

Verificado con `luac -p`, desplegado en ambos destinos.

**Prueba pendiente para Dragón:** acariciar/alimentar varios Pals salvajes distintos y revisar el log en busca de líneas `[PERSONALITY-ROLL]` — confirmar que aparecen los 4 tipos de tirada con una mezcla que se vea razonable (aprox. la mitad "normal") y que nada da error.

**Parte B — ENFORCEMENT (investigación en curso, sin tocar código de comportamiento todavía):** que un Pal tenga guardado "es hostil" no sirve de nada todavía si el juego no actúa distinto de verdad. Se investigó el mod "PassiveWildPals" que Dragón ya tenía descargado en la carpeta del proyecto (`Proyectos\32-PalBonds\PassiveWildPals (Steam)...`), asumiendo (correctamente) que su mecanismo sería el mismo que necesitamos, solo que al revés.

Se extrajo (con la herramienta `repak`, ya usada antes en este proyecto) el mismo archivo que reemplaza el mod pacifista (`BP_AIAction_WildLife`, el Blueprint maestro de decisión de IA de todo Pal salvaje) directamente del pak principal del juego SIN MODIFICAR, y se comparó byte a byte contra la versión del mod. Diferencia real encontrada: la versión del mod agrega 3 nombres nuevos a su tabla de símbolos que la versión original no tiene: `GetBattleManager`, `PalBattleManager`, y `TargetIsPlayerOrPlayersOtomoPal` — es decir, el mod agrega una llamada nueva dentro de la lógica de decisión que pregunta "¿este objetivo es el jugador o el Otomo del jugador?" y usa eso para bloquear la respuesta de combate. Confirma exactamente lo que Dragón sospechaba: el mod pacifista y nuestro sistema de personalidad tocan la misma maquinaria del juego.

**Hallazgo propio, independiente del mod (potencialmente más útil todavía):** revisando el volcado de cabeceras del juego (`Pal.hpp`) se encontró la clase real `UPalAIResponsePreset` — el mismo tipo de objeto que este mod ya lee para detectar la disposición natural de una especie (`BP_AIResponsePreset_friendly_C`, etc.) — y tiene 8 campos simples, uno por situación exacta: `Discover_Player`, `Discover_Greater`, `Discover_Equal`, `Discover_Smaller`, `Damaged_Player`, `Damaged_Greater`, `Damaged_Equal`, `Damaged_Smaller`. Cada Pal accede al suyo a través de `AISensorComponent.AIResponsePreset` (un puntero). Esto es exactamente la tabla que decide "qué hago si veo al jugador / me lastima el jugador", por especie.

**Por qué esto importa y por qué NO se implementó todavía sin avisar:** ese objeto de preset normalmente es COMPARTIDO por todos los Pals de la misma especie (no es un dato por individuo) — escribirle encima directamente cambiaría el comportamiento de TODOS los Pals de esa especie a la vez, no solo el que tiró "hostil". Ese es exactamente el tipo de error ya sufrido antes en este proyecto (pasadas 18 y 82: escribir sobre estado compartido del juego sin verificar primero). La idea seguraque se propone para la próxima pasada, pendiente de luz verde de Dragón: en vez de modificar el preset compartido, simplemente cambiar a qué preset EXISTENTE apunta el puntero `AIResponsePreset` de ESE Pal específico (redirigir el puntero, no editar el objeto al que apunta) — el mismo patrón ya usado con éxito en la pasada 88 para `IndividualHandle`. Falta encontrar/confirmar una instancia ya cargada de un preset "hostil" y uno "miedoso" para poder apuntar ahí.

Ningún archivo de comportamiento de IA fue modificado esta pasada — todo lo de la Parte B fue investigación de solo lectura sobre archivos del juego y de un mod de terceros, sin tocar el mod propio ni el estado real de ninguna partida.


## Continuación 67 (2026-09-03): primer intento real de ENFORCEMENT de personalidad — pendiente de prueba en vivo

Con luz verde de Dragón sobre el diseño (el cambio de personalidad debe notarse apenas el Pal está cerca, no solo después de acariciarlo), se implementó el primer intento real de que la personalidad tirada afecte de verdad el comportamiento del Pal.

**Cómo funciona:** cada Pal salvaje tiene un objeto compartido (`AIResponsePreset`) que decide "qué hago si veo/me lastima el jugador" — compartido por TODA su especie, no por individuo. En vez de editar ese objeto compartido (cambiaría a toda la especie de golpe, el mismo error ya sufrido en las pasadas 18 y 82), se agregó un chequeo recurrente cada 8 segundos que recorre los Pals salvajes cercanos y, para cualquiera que haya tirado una personalidad distinta de "normal", busca OTRO Pal salvaje ya cargado en el mundo cuya especie use naturalmente el preset que corresponde (Warlike→hostil, escape→miedoso, friendly→curioso — de solo 11 presets reales que existen en todo el juego, confirmados extrayendo los datos del propio juego) y apunta el puntero de ESE Pal específico hacia ese objeto ya existente y ya probado. Nunca se edita el objeto compartido, nunca se toca un Pal ya capturado.

**Lo que todavía no está confirmado (sin probar en vivo):** si escribir ese puntero desde Lua realmente cambia el comportamiento del Pal en el juego, o si el chequeo cada 8 segundos genera lag notable.

Verificado con `luac -p`, desplegado en ambos destinos.

**Prueba pendiente para Dragón:** quedarse cerca de Pals salvajes un par de minutos (no hace falta interactuar, el chequeo corre solo) y revisar el log en busca de líneas `[ENFORCE]`. Una línea `SUCCESS` es la primera prueba de que el mecanismo corre; la prueba real es ir a ver a ESE Pal específico en el juego y confirmar si de verdad ataca/huye/observa distinto a como su especie haría normalmente. Avisar también si se nota más lag que antes.


## Continuación 68 (2026-09-03): lag real encontrado y arreglado en la primera prueba en vivo — causa del "no vi nada distinto" explicada

Dragón probó ambos frentes en una sola sesión y reportó: lag notable, ningún cambio visible de personalidad, y el menú de trabajador sin abrirse con los Pals salvajes.

**Lag — confirmado y arreglado.** El log mostró **2813** líneas idénticas de diagnóstico en menos de 3 minutos — casi la mitad de TODO el log de la sesión. Causa real: el código que buscaba "otro Pal ya cargado que use el preset que necesito" repetía una consulta pesada (con su propio registro en el log) contra CADA Pal cercano, CADA VEZ que un Pal sin resolver todavía lo necesitaba — con el chequeo cada 8 segundos y varios Pals sin resolver, eso se multiplica exactamente en este tipo de spam, la misma clase de bug de lag ya vista antes en este proyecto. Arreglado: ahora se arma UNA sola lista de "qué Pal ya tiene qué preset" por cada chequeo, reutilizando datos ya calculados, en vez de volver a preguntar por cada Pal sin resolver.

**Por qué no se vio ningún cambio de personalidad.** Las 2813 líneas eran todas el mismo error: el puntero al "preset" de comportamiento salía nulo/vacío para prácticamente todos los Pals esta sesión — un tipo de fallo nunca visto antes en este proyecto (las pruebas anteriores siempre fallaban de otra forma distinta). Con el puntero vacío, nunca se pudo encontrar ningún "donante" real para ningún nivel de personalidad. Se agregó un reintento: ahora, si la primera lectura falla, se vuelve a intentar en cada chequeo siguiente en vez de quedar atascado para siempre — si el problema era que el Pal estaba recién aparecido en el momento exacto de la primera lectura, esto debería autocorregirse solo. Si el problema es más profundo, todavía no lo sabemos — hace falta otra prueba en vivo para confirmar.

**Frente del menú radial:** las 2 líneas reales `[WORKASSIGN-DIAG]` de esta sesión vinieron de un Sheepball real, asignado a trabajar en la base (con datos reales de asignación de trabajo) — coincide con la teoría. Pero los intentos de presionar "4" sobre el Lamball/Chikipi salvajes esta vez ni siquiera llegaron a registrarse en el sistema de interacción del juego — no fue un problema de "qué menú elegir", sino que el juego no detectó ningún objetivo interactivo en ese momento (probablemente un problema de distancia/ángulo, como en pruebas mucho más antiguas de este proyecto).

Verificado con `luac -p`, desplegado en ambos destinos.

**Prueba pendiente para Dragón:** repetir ambas pruebas. Para personalidad: pasar un par de minutos cerca de Pals salvajes y avisar si el lag mejoró y si aparece alguna línea `[ENFORCE] SUCCESS` en el log. Para el menú radial: acercarse bien y apuntar con cuidado a un Pal salvaje antes de presionar "4" — si de nuevo no pasa NADA (ni siquiera se abre el menú sin apuntar), eso ya es información útil por sí sola (un problema de puntería/rango, no del menú en sí).


## Continuación 69 (2026-09-03): segundo lag arreglado, pregunta real sobre el momento correcto de la lectura, y el mod "RemoteAccessEverything" resuelto

Segunda prueba de Dragón: menos lag que antes pero todavía notable, sin cambios de personalidad ni de menú. El log confirmó: se encontró y arregló una SEGUNDA fuente de spam (otra línea de log que se repetía sin parar, esta vez del lado de "no encontré un Pal donante todavía" — 221 líneas en esta prueba) con el mismo arreglo de "avisar solo una vez" que ya se usó antes.

**El hallazgo más importante:** el reintento agregado la pasada anterior nunca tuvo éxito ni una sola vez en 3 minutos completos. Eso apunta a algo más profundo que "el Pal estaba recién aparecido": TODAS las veces anteriores en que este proyecto logró leer el dato de comportamiento de un Pal, fue durante una interacción real (acariciar/alimentar) — nunca solo por estar cerca. Es posible que ese dato del juego no esté realmente listo hasta que el Pal tiene una interacción real con el jugador, lo cual chocaría directamente con el objetivo de Dragón (que la personalidad se note ANTES de acercarse). **Antes de escribir más código a ciegas**, la prueba pendiente es: acariciar o alimentar un Pal salvaje como siempre, y revisar si en el log aparece una línea que diga "resolved on retry" justo después — eso confirmaría o descartaría la teoría sin necesitar código nuevo.

**Sobre "RemoteAccessEverything":** confirmado con la misma técnica de extracción — modifica un menú completamente distinto (el menú del jugador sin apuntar, no el menú de trabajador que estamos investigando) y solo agrega acceso remoto a las cajas de almacenamiento (Palbox) desde cualquier lugar. No tiene relación con Pals salvajes ni con lo que estamos armando.

Verificado con `luac -p`, desplegado en ambos destinos.

**Prueba pendiente:** acariciar/alimentar UN Pal salvaje (como siempre se ha hecho) y avisar si el log muestra una línea "resolved on retry" cerca de ese momento.


## Continuación 70 (2026-09-03): Dragón encontró el hueco real en el arreglo anterior — botones grises, corregido

Dragón reportó que Acariciar/Alimentar aparecían en gris (imposibles de presionar) en el menú del jugador al apuntar a un Pal salvaje. Mi primera lectura fue pesimista: pensé que era una verificación real y profunda de "es este realmente mi Pal de party" (datos de guardado, no algo seguro de falsificar).

Dragón cuestionó esa conclusión con una idea mejor: en vez de falsificar datos reales, ¿por qué no simplemente cambiar la RESPUESTA a la pregunta que bloquea los botones? — la misma técnica que ya usamos para arreglar el menú de trabajador. Volviendo a revisar el código existente con esa idea en mente, apareció una explicación mucho más simple: la sustitución que ya existía (de hace varias pasadas) solo se aplicaba UNA vez por apertura del menú, pero el juego pregunta "¿cuál es mi Otomo?" varias veces por segundo mientras el menú está abierto — así que lo más probable es que la pregunta que realmente decide si los botones se activan nunca llegó a ver nuestra sustitución, porque ocurrió en una de esas llamadas posteriores que dejamos sin tocar a propósito.

**Arreglo aplicado:** ahora la sustitución se aplica en CADA llamada mientras el menú sigue abierto, no solo la primera. Mismo código ya probado, solo se quitó un límite que nosotros mismos habíamos puesto.

Verificado con `luac -p`, desplegado en ambos destinos.

**Prueba pendiente y bien específica para Dragón:**
1. Entra al juego.
2. Busca cualquier Pal salvaje (uno que NO sea tuyo — sin correa, sin nombre que hayas puesto).
3. Acércate lo suficiente como para poder interactuar normalmente con algo (a pocos pasos).
4. Apunta la cámara directo al cuerpo del Pal (no al piso cerca de él, ni a través de pasto/rocas).
5. Presiona la tecla "4" una vez.
6. Fíjate si el menú se abre y si Acariciar/Alimentar aparecen en color normal (activos) o en gris (bloqueados) esta vez.
7. Avisa exactamente qué viste — no hace falta hacer nada más todavía, ni presionar Acariciar. Solo reportar si están grises o no esta vez.

Segunda prueba, sin relación, más simple, para el otro frente (personalidad):
1. Busca cualquier Pal salvaje.
2. Acarícialo o aliméntalo como siempre lo has hecho (F9/F10, el método normal de este mod).
3. Avísame que lo hiciste — yo reviso el log después.

## Continuación 71 (2026-09-03): la prueba de la pasada 96 nunca llegó a probar el arreglo — el registro de hooks se rindió antes de tu primer "4"

Volviste a probar (Acariciar/Alimentar en el menú del jugador, luego el menú de trabajador con PupperAI y Lamball) y los botones seguían grises. Antes de pedirte otra prueba, revisé el log completo de esa sesión (12:05:30 a 12:08:12) y encontré algo importante: esa prueba en realidad NUNCA llegó a poner a prueba el arreglo de la Continuación 70.

Lo que encontré: el sistema que "engancha" (hookea) las funciones del menú del jugador reintenta durante un tiempo limitado si no las encuentra de inmediato — hasta ahora, 8 intentos separados por 5 segundos, o sea 40 segundos en total desde que el mod carga. En esta sesión, TODOS los intentos fallaron los 8 rounds, y el sistema se rindió a los ~37 segundos después de cargar (12:06:07) — pero tu primer "4" no fue hasta 12:07:39, casi 90 segundos DESPUÉS de que el sistema ya se había rendido. Es decir: cuando presionaste "4", el enganche que activa la ventana de sustitución ni siquiera estaba puesto. No es que el arreglo de la pasada anterior no funcione — es que nunca llegó a ejecutarse.

Esto mismo (rendirse a los 8 intentos, antes de que hicieras tu primera acción) le pasó también a los otros 4 sistemas de enganche parecidos en el mismo archivo (el del menú de trabajador y el de los indicadores), todos casi al mismo segundo — lo que sugiere que esas partes de la interfaz del juego simplemente tardan más en cargar en memoria de lo que el mod esperaba, no que los nombres de función estén mal (la mayoría de esos nombres ya están confirmados como reales en pruebas anteriores).

**Arreglo aplicado:** extendí el tiempo de reintento de 8 intentos/40 segundos a 60 intentos/5 minutos. Dejé un límite (no reintento infinito) porque un par de nombres de función en esa lista todavía no están 100% confirmados como reales, y ya tuvimos dos veces antes un problema de lag por reintentar sin límite — pero 5 minutos debería sobrar para cubrir el tiempo real que tardás en llegar a tu primer "4" en una partida normal.

Verificado con `luac -p`, desplegado en ambos destinos. **No subo el progreso todavía** — esto arregla un problema de infraestructura (el enganche ni se estaba poniendo), pero todavía no sabemos si, una vez que SÍ se pone, el botón de Acariciar/Alimentar se activa o sigue gris por otra razón real. Eso lo sabremos con la próxima prueba.

**Prueba pendiente, paso a paso:**
1. Entra al juego con el mod instalado.
2. Esta vez esperá un poco más antes de la primera prueba — con este arreglo tenés hasta 5 minutos desde que cargás, así que no hay apuro, pero tampoco hace falta esperar los 5 minutos completos.
3. Buscá cualquier Pal salvaje (uno que no sea tuyo — sin correa, sin nombre puesto por vos).
4. Acércate lo suficiente para poder interactuar normalmente (a pocos pasos).
5. Apuntá la cámara directo al cuerpo del Pal (no al piso cerca de él, ni a través de pasto o rocas).
6. Presioná la tecla "4" una vez.
7. Fijate si el menú se abre y si Acariciar/Alimentar aparecen en color normal (activos) o en gris (bloqueados).
8. Avisame exactamente qué viste esta vez — con esto ya sabemos si el problema real era solo este tiempo de espera, o si hay algo más bloqueando los botones.

## Continuación 72 (2026-09-03): CONFIRMADO — no había un muro de propiedad real, y encontramos el punto exacto para conectar la acción real

¡Buenas noticias reales! Con el arreglo del tiempo de espera, el menú del jugador finalmente se armó a tiempo: la sustitución ocurrió dos veces (una vez con un Plantslime salvaje, otra con un Sheepball salvaje), y Acariciar/Alimentar NO aparecieron en gris — los pudiste clickear. Esto confirma que la teoría de la Continuación 70 era correcta: nunca hubo un muro real y profundo de "verificación de propiedad" — todo el bloqueo era nuestro propio límite de "una sola vez por ventana" combinado con el problema de tiempo de espera, y ambos ya están arreglados.

Mejor todavía: el log muestra que al clickear, sí se dispara la lógica real de decisión del juego sobre el Pal salvaje sustituido (no solo el botón se ve activo — el juego realmente "escucha" el click). Que no haya pasado nada visible es esperado, no un bug: desde el incidente de la pasada 82 (donde un Pal tuyo ya propio fue recapturado sin querer), decidimos a propósito NO conectar esa decisión a una acción real todavía, solo mirar y registrar. Ahora ya tenemos el punto exacto donde conectar la acción real (acariciar/alimentar de verdad al Pal salvaje), con la misma protección de "¿ya es mío?" que ya usan F9/F10 para evitar que se repita ese incidente.

**Lag nuevo, encontrado y arreglado en el mismo pase:** dijiste que esta prueba se sintió "terriblemente lageada", peor que antes. Revisé el log y encontré que fue un efecto secundario de mi propio arreglo anterior (el de esperar más tiempo): unos pocos nombres de función que nunca existen de verdad en esas clases del juego (confirmado real, no adivinado — sus nombres "hermanos" en la misma clase sí se engancharon rápido, probando que la clase carga bien) se quedaban reintentando cada 5 segundos durante mucho más tiempo que antes (hasta 5 minutos en vez de 40 segundos), y cada intento fallido escribía un bloque de error de ~10 líneas en el log en vez de 1. Arreglado: ahora el log de error es de 1 línea (misma información, sin el texto repetido de siempre), y en cuanto una clase demuestra que ya cargó (algún hermano se enganchó bien), a los nombres que sigan fallando se les dan solo 3 intentos más antes de dejarlos — ya no tiene sentido seguir esperando 5 minutos completos para un nombre que sabemos que está mal.

Verificado con `luac -p`, desplegado en ambos destinos.

**Prueba pendiente:**
1. Entra al juego con el mod instalado (versión más nueva ya está puesta).
2. Repetí lo mismo de la vez pasada: buscá un Pal salvaje, apuntá, presioná "4", y clickeá Acariciar o Alimentar si aparecen activos.
3. Fijate si esta vez se siente menos pesado/lageado que la prueba anterior.
4. Avisame qué tal se sintió — con esto confirmamos si el arreglo del lag funcionó.

No hace falta que hagas nada más todavía con la parte de "conectar la acción real" — eso lo charlamos antes de tocar código, dado lo que pasó la vez pasada con la recaptura sin querer.

## Continuación 73 (2026-09-03): conectada la acción real de Acariciar/Alimentar para Pals salvajes desde el menú del jugador

Dijiste que sí, que la conectemos ahora. Lo hice reutilizando TODO lo que ya está probado desde hace mucho: cuando cerrás el menú del jugador después de haber clickeado Acariciar o Alimentar sobre un Pal salvaje, el mod ahora llama a la MISMA función que usan las teclas F9/F10 de toda la vida — el mismo apuntado real, la misma protección de "no hacer nada si ya estás en medio de otra animación", y la misma protección de "no tocar nada si el Pal ya es tuyo de verdad" que agregamos después del incidente de la Petallia. No escribí lógica nueva de acariciar/alimentar — solo conecté el botón del menú a la función que ya sabíamos que funciona bien.

Una decisión importante: el juego manda una señal ambigua cuando decidís Acariciar vs Alimentar (un valor "verdadero/falso" cuyo significado exacto todavía no confirmamos con certeza) — en vez de adivinar qué significa ese valor y arriesgarme a conectarlo mal, hice que el mod solo se fije EN QUÉ EVENTO se disparó (Acariciar o Alimentar), ignorando ese valor ambiguo. Y lo más importante: esto solo puede pasar en ventanas donde de verdad sustituimos un Pal salvaje — nunca va a tocar a tus propios Pals a través de este camino nuevo, así que no hay riesgo de que se dupliquen animaciones o cariño en tus Pals ya capturados.

Verificado con `luac -p`, desplegado en ambos destinos.

**Prueba pendiente — dos partes, la primera es solo para confirmar que no rompimos nada:**

**Parte 1 (chequeo de que tus Pals siguen funcionando igual que siempre):**
1. Entra al juego.
2. Acaricia o alimenta a tu propio Pal (uno que ya sea tuyo, de tu equipo) usando el menú del jugador, como siempre lo hiciste.
3. Fijate que se vea y se sienta exactamente igual que siempre — una sola animación, el cariño sube normal, nada raro ni duplicado.

**Parte 2 (la función nueva):**
4. Buscá un Pal salvaje (que no sea tuyo).
5. Apuntá con la cámara al Pal y presioná "4".
6. Clickeá Acariciar (o Alimentar).
7. Fijate si esta vez SÍ pasa algo de verdad — si el Pal reacciona con la animación de acariciado/alimentado.
8. Avisame qué viste, y también contame si sentiste menos lag que la prueba anterior.

## Continuación 74 (2026-09-03): encontrada la causa real de por qué Acariciar/Alimentar funcionaba a veces sí y a veces no

Tu teoría iba en la dirección correcta, pero la causa real resultó ser distinta y la encontré revisando los tiempos exactos en el log: el sistema interno que "recuerda" que sustituimos un Pal salvaje tenía un cronómetro de seguridad de solo 1.5 segundos (por si el menú no avisaba que se cerró). El problema es que vos tardaste más de 1.5 segundos en decidir y clickear en varios de los intentos — con el Gummoss y con el segundo intento del Lamball, la decisión real llegó 3-4 segundos después de abrir el menú, cuando ese cronómetro interno ya se había "olvidado" de que había un Pal salvaje sustituido. El juego en sí nunca se confundió (por eso el botón seguía funcionando) — fue nuestro propio código el que ya había dejado de prestar atención para cuando clickeaste.

No es exactamente que "el Pal estaba ocupado" (esa parte del juego sigue funcionando igual que siempre) — es más bien que nuestro propio cronómetro interno era demasiado corto para el tiempo real que tardás en decidir.

**Arreglo:** extendí ese cronómetro de 1.5 segundos a 15 segundos — de sobra para cualquier tiempo real que uses para apuntar y decidir. También encontré y arreglé un segundo bug relacionado: la señal que dice "esto es un Pal salvaje sustituido, es seguro actuar" se estaba activando SIEMPRE que el menú estaba abierto, incluso con tus propios Pals — por pura casualidad de orden de eventos no llegó a causar un problema real esta vez, pero lo arreglé para que ahora solo se active cuando de verdad sustituimos un Pal salvaje.

**Sobre tu otra pregunta** (¿qué pasa si el Pal empieza otra animación entre que abrís el menú y clickeás Acariciar?): no pasa nada malo — el mod revisa si el Pal está libre justo en el momento de actuar, y si ya está ocupado con otra cosa, simplemente no hace nada (como el juego normal: no podés acariciar a un Pal ocupado). No fuerza ni interrumpe nada.

**Sobre el lag:** revisé el log de esta prueba y el arreglo del lag de la vez pasada SÍ funcionó de verdad — el archivo de log bajó de 1MB a 448KB en una sesión de duración parecida, y los errores repetidos (tracebacks) bajaron de 794 a solo 2, y esos 2 son cosas viejas sin relación con lo que arreglamos, y solo pasan una vez, no en bucle. Si todavía sentís lag, ya no parece venir de este sistema — puede ser otra cosa que no hemos identificado todavía.

Verificado con `luac -p`, desplegado en ambos destinos.

**Prueba pendiente:**
1. Entra al juego.
2. Acaricia/alimenta a tu propio Pal como siempre (chequeo rápido de que nada se rompió).
3. Buscá un Pal salvaje, apuntá, presioná "4".
4. Esta vez, tomate tu tiempo a propósito — esperá 3, 4, hasta 5 segundos antes de clickear Acariciar o Alimentar (para probar justo el caso que antes fallaba).
5. Fijate si esta vez SÍ funciona incluso tomándote ese tiempo.
6. Avisame qué tal salió.

## Continuación 75 (2026-09-03): el arreglo del timeout funciona muy bien (21 de 25), el lag queda anotado como pendiente, y estado real de las personalidades

Buenas noticias primero: en esta prueba, la acción real de Acariciar/Alimentar se disparó 21 de las 25 veces que presionaste "4" — un salto grande comparado con antes. El arreglo del cronómetro (Continuación 74) está funcionando de verdad.

**Sobre el pedazo de log que pegaste** (esa seguidilla de errores "RegisterHook... FAILED"): no es un bug nuevo, es el mismo sistema de reintento que ya conocíamos (el que espera a que el juego termine de cargar los menús) haciendo su trabajo — esta vez tardó hasta el intento número 11 (~55 segundos) en vez del 4 de la prueba pasada, por eso se vio como "más" errores, pero se sigue deteniendo solo como debe. Confirmé que solo hubo 2 errores de los "graves" (con el texto largo repetido) en toda la sesión, así que el arreglo de la vez pasada sigue funcionando bien ahí.

**El tranco/freeze real que sentís cada vez que presionás "4"** es algo distinto y todavía no lo aislamos — no puede ser por esa seguidilla de arriba (esa solo pasa una vez, al principio de la sesión, no en cada apertura de menú). Los sospechosos son: (1) el trabajo que hace el mod cada vez que sustituye el Pal salvaje (busca a quién estás apuntando, como 4 veces por segundo mientras el menú está abierto), o (2) el costo de escribir tanto en el log. Como pediste, lo anoté en la lista de pendientes técnicos (`DESIGN.md`, sección 10, "Performance & polish backlog") en vez de intentar arreglarlo a ciegas — hace falta aislar cuál de los dos sospechosos es el real antes de tocar código ahí.

**Sobre las personalidades:** no dejé de preguntar por descuido — en realidad cada prueba que hacemos del menú radial YA incluye acariciar/alimentar Pals salvajes, que es exactamente el chequeo que necesitamos para saber si el misterio de personalidad se resolvió. Y la respuesta sigue siendo la misma de hace varias pasadas: no, sigue sin resolverse — "resolved on retry" salió 0 veces de nuevo esta sesión, la personalidad de base de cada especie sigue leyéndose siempre como "curious" (el fallback), no la real. Lo que SÍ sigue funcionando bien es el sorteo de personalidad por individuo (tímido/hostil/curioso/normal) — eso tiene variedad real, no está roto. El misterio de por qué no podemos leer la personalidad real de la especie sigue abierto y en pausa, no es una prioridad activa ahora mismo mientras seguimos con el menú radial — lo retomamos cuando quieras.

No hubo cambios de código en esta pasada, así que no hace falta que hagas una prueba nueva por esto — seguí con lo que ya venías haciendo.

## Continuación 76 (2026-09-03): perseguimos el "hitch" (tirón/freeze corto) al presionar "4"

**Contexto:** Dragón reportó que cada vez que presiona "4" cerca de un Pal salvaje, el juego se traba por una fracción de segundo — corto, pero notable. Le pedí que eligiera qué atacar primero (el misterio de personalidades, el tirón de rendimiento, o los datos de Worker Menu), y eligió el tirón de rendimiento.

**Qué encontré:** la función que revisa a qué Pal estás apuntando (`find_targeted_pal`) hace un escaneo completo de TODOS los Pals cargados en el mapa, cada vez que se llama. Y se estaba llamando hasta 4 veces por segundo, durante todo el tiempo que el menú radial está abierto — que ahora puede ser hasta 15 segundos (por el cambio del pase anterior). Eso significa que un solo "4" podía disparar hasta 60 escaneos completos del mapa. Es un costo real y medible, no una suposición.

**Qué hice:** ahora ese escaneo solo se repite como máximo una vez cada 0.25 segundos (un cuarto de segundo). Mientras tanto, se reutiliza el último resultado. Tu puntería no cambia tan rápido como para necesitar más que eso, así que no debería notarse ninguna diferencia en cómo responde el menú al Pal que estás mirando.

También agregué una línea nueva en el log, `[RADIAL-REDIRECT-PERF]`, que mide en milisegundos cuánto tarda ese escaneo cada vez que sí se ejecuta. Esto nos va a dar números reales para confirmar (o descartar) si este era el verdadero causante del tirón.

**Importante:** este cambio está reduciendo la frecuencia del escaneo costoso, pero todavía NO he confirmado en vivo si esto realmente elimina el tirón que sientes. Por eso necesito que hagas la prueba de nuevo.

**Cómo probar (dos partes):**

1. Prueba de sensación: acércate a un Pal salvaje y presiona "4" varias veces (al menos 5-6 veces, en distintos Pals si puedes). Presta atención a si el tirón/freeze corto sigue estando igual de notable, se siente mejor, o desapareció por completo.

2. Prueba de números: después de jugar un rato, dime y yo reviso el log en busca de líneas que digan algo como:
   `[RADIAL-REDIRECT-PERF] find_targeted_pal scan took X.XXms`
   Esos números en milisegundos me van a decir si esta función realmente estaba tardando lo suficiente como para causar el tirón que sientes, o si el verdadero causante está en otro lado (por ejemplo, en cómo se escribe el log, o en la construcción de la interfaz del menú del propio juego).

No necesitas copiar y pegar el log tú mismo — yo lo leo directamente. Solo dime cuando hayas probado y yo reviso.

## Continuación 77 (2026-09-03): elegí "Feed con comida real" de tu lista de features, Etapa 1 (solo investigación)

**Contexto:** hiciste una prueba nueva y fuiste honesto: el juego sigue sintiéndose con lag a pesar del throttle del pase anterior. Investigué el log y confirmé por qué: cada escaneo real cuesta entre 36 y 50 milisegundos, y como ese escaneo se resetea cada vez que abrís el menú con "4", el primer escaneo de cada apretón de tecla siempre paga ese costo completo, sin importar el throttle. Documenté esto en detalle en los archivos técnicos, pero como vos mismo pediste dejar el rendimiento para más adelante, no toqué nada más de eso por ahora.

También me pasaste una lista larga de features pendientes y me dejaste elegir cuál atacar. Elegí: **que "Feed" (alimentar) use un item de comida real de tu inventario**, en vez de solo jugar la animación sin gastar nada (que es lo que hace ahora). Elegí esta porque: (1) ya estaba anotado como una limitación conocida desde hace mucho, y (2) es justo lo que hace falta para que las "kinship peaches" (duraznos de amistad) funcionen, como vos mismo explicaste.

**Qué encontré (investigación real, no inventada):** en los archivos de datos del juego encontré la función real que probablemente entrega un item de comida a un Pal (`SelectedFeedingItem`), y una categoría de item DEDICADA a dar puntos de amistad (`ConsumePalGainFriendshipPoint`) separada de la comida normal — esto es casi seguro lo que vos llamás "kinship peaches", ya existe en los datos del juego.

**Qué hice esta vez (SOLO lectura, nada que cambie el juego todavía):** seguí la misma regla de siempre — nunca escribir sobre datos reales del juego (como tu inventario) sin antes confirmar con diagnósticos de solo lectura. Así que esta vez solo agregué:

1. Un "espía" permanente que registra en el log si el juego mismo llama a esa función de alimentar-con-item alguna vez durante tu partida (sin que nosotros hagamos nada).
2. Un diagnóstico que se dispara cada vez que presionás F10 (alimentar), que intenta leer qué comida real tenés en tu inventario y lo escribe en el log. Esto es un experimento — es la primera vez que probamos llamar a esta función particular, así que puede fallar, y si falla, el log me va a decir exactamente por qué, para poder corregirlo la próxima vez (así resolvimos el menú de Worker Menu hace varios pases).

**Importante:** F9 (pet) y F10 (feed) siguen funcionando exactamente igual que antes. No cambié nada del comportamiento real todavía — solo agregué "espías" que escriben en el log, nada más. Esto es la Etapa 1 de 4 etapas para esta feature completa (etapa 2: encontrar el item exacto en tu inventario; etapa 3: realmente gastar el item; etapa 4: que se abra un menú real para que vos elijas qué comida usar, que es lo que pediste originalmente).

**Cómo probar:**

1. Anda cerca de cualquier Pal (tuyo o salvaje) y asegurate de tener al menos un item de comida real en tu inventario (carne, bayas, algún plato, etc.).
2. Presioná F10 (alimentar) como siempre.
3. Nada debería verse diferente en el juego — la animación de alimentar debería funcionar igual que siempre.
4. Después, avisame y yo reviso el log buscando líneas que digan `[FOOD-DIAG]` — ahí vamos a ver si el experimento funcionó o no, y en cualquier caso vamos a tener información real para seguir avanzando.

No hace falta que copies nada del log — yo lo leo directamente cuando me avises que probaste.

## Continuación 78 (2026-09-03): primera confirmación real de la función de alimentar + arreglé un diagnóstico que nunca se iba a activar

**Contexto:** dijiste que de ahora en adelante vas a probar todo usando SOLO el menú radial (tecla "4"), no F9/F10 directamente, para que cualquier diferencia de comportamiento entre los dos caminos salga a la luz. Hiciste una prueba real: alimentaste a un Chikipi salvaje (dos veces), a tu Otomo activo (Foxparks), y a un Pal asignado como trabajador en tu base.

**Lo que encontré revisando el log:**

1. El Chikipi salvaje: funcionó exactamente como antes, sin abrir inventario, sin gastar nada — esto es esperado, es la aproximación que ya tenemos para Pals salvajes, no cambió.

2. Uno de los dos Pals tuyos (Otomo activo o el trabajador de base, todavía no puedo confirmar cuál de los dos con certeza) SÍ disparó la función real del juego para "entregar este item de comida" — con datos reales: un slot de inventario real, cantidad real. Esta es la PRIMERA confirmación en vivo de que encontramos la función correcta del juego para esto. Buena noticia para seguir avanzando con la feature.

3. Cosa rara: solo se registró UNA vez esa función, a pesar de que alimentaste a DOS pals tuyos (el Otomo y el trabajador). Pregunta para vos: ¿alimentar al trabajador de base fue igual de "abrió inventario, elegiste bayas" que con el Otomo? Si tenés manera de recordar el orden exacto o si notaste alguna diferencia entre esos dos casos, me ayuda mucho a entender qué está pasando.

4. Encontré y arreglé un error mío: el diagnóstico que agregué la vez pasada (el que revisa qué comida real tenés) estaba conectado solo a la tecla F10 física — como ahora vas a probar solo con el menú radial, ese diagnóstico NUNCA se iba a activar con tu forma de probar. Ya lo moví para que se dispare sin importar si viene de F10 o del menú radial.

**Importante:** nada del comportamiento real de Pet/Feed cambió. Todo esto sigue siendo solo lectura de logs, ningún gasto de items todavía.

**Cómo probar:**

1. Alimentá un par de Pals más usando el menú radial — un salvaje, tu Otomo activo, y si es fácil, un trabajador de base otra vez.
2. Avisame cuando hayas probado y reviso el log buscando:
   - Si ahora sí aparece la línea de diagnóstico de "qué comida tenés" (antes nunca aparecía por el error que arreglé).
   - Si aparece una segunda vez la función real de alimentar, y para qué tipo de Pal, para entender mejor la pregunta rara del punto 3 de arriba.

Como siempre, no hace falta que copies el log — yo lo reviso directamente.

## Continuación 79 (2026-09-03): confirmado — tu Otomo activo y un Pal trabajador de base usan funciones distintas para alimentar

**Contexto:** hiciste la prueba ordenada que pedí — alimentar y luego acariciar a un Lamball salvaje, después a tu Otomo activo Foxparks, después a tu Chikipi asignado como trabajador de base. Gracias por el orden claro, me sirvió muchísimo para entender qué pasó cuándo.

**Lo que confirmé revisando el log:**

1. El Lamball salvaje: funcionó exactamente igual que siempre (nuestra propia versión, sin inventario, sin gastar nada). Sin cambios.

2. Foxparks (tu Otomo activo): confirmé que alimentarlo Y acariciarlo con el menú radial es 100% del juego original — nuestro mod ni se entera, solo lo estamos "espiando" desde afuera. Y lo importante: la función que encontramos la vez pasada (`SelectedFeedingItem`) NO se activó para Foxparks.

3. Tu Chikipi trabajador de base: la función SÍ se activó de nuevo, con datos reales (qué slot de inventario, cuánta cantidad). Esta es la segunda vez que se confirma, con dos Pals trabajadores distintos en dos pruebas distintas.

**Conclusión real (ya no es una sospecha, son dos pruebas que lo confirman):** aunque para vos alimentar a tu Otomo activo y alimentar a un Pal trabajador de base SE VE igual (ambos abren un inventario para elegir comida), por dentro el juego usa DOS funciones distintas. Ya encontramos cuál es la de los trabajadores de base. La de tu Otomo activo todavía no la encontramos — es la próxima pregunta a resolver si queremos que alimentar funcione igual para Pals salvajes que para tu propio Otomo.

**Además:** el diagnóstico de "qué comida tenés" ya se activó esta vez (arreglé bien el problema de la vez pasada), pero todavía no devolvió información útil — no dio error, pero tampoco trajo datos reales todavía. Agregué un segundo intento con una forma distinta de llamar a esa función, a ver si esta vez sí funciona. Los dos intentos van a quedar registrados en el log por separado.

**Cómo probar:**

1. Alimentá cualquier Pal con el menú radial (no importa cuál — salvaje, tu Otomo, o un trabajador, cualquiera sirve para este diagnóstico en particular).
2. Avisame y reviso el log buscando las líneas de "Attempt A" y "Attempt B" para ver si alguna de las dos formas nuevas de preguntar por tu comida funcionó.

Como siempre, avisame nomás cuando hayas probado, yo reviso el log directamente.

## Continuación 80 (2026-09-03): encontré por qué el diagnóstico de comida no traía datos, y una tercera confirmación de la diferencia Otomo/trabajador

**Contexto:** repetiste la misma prueba de siempre (salvaje, Otomo, trabajador) y esta vez el log me dio la respuesta clara a dos preguntas que tenía pendientes.

**1. Confirmado por tercera vez:** un Pal trabajador de base (esta vez un Daedream) volvió a disparar la función real de "entregar comida", y esta vez con datos que confirman al 100% que es un trabajador de base de verdad. Tu Foxparks (Otomo activo) de nuevo NO la disparó. Con tres pruebas separadas mostrando lo mismo, ya es un hecho confirmado, no una sospecha: alimentar a tu Otomo activo y alimentar a un trabajador de base, aunque se ven idénticos en pantalla, usan funciones distintas del juego por dentro.

**2. Resuelto el misterio del diagnóstico de comida:** uno de mis dos intentos anteriores directamente falló con un error claro del juego ("se esperaban 4 parámetros, se recibieron 3") — esto en realidad es una buena noticia, porque confirma que la firma de la función que tenía anotada es exactamente correcta. El otro intento no daba error, pero tampoco traía nada — y ahora entiendo por qué: estaba revisando el lugar equivocado. Esa función no "devuelve" nada (técnicamente no tiene valor de retorno), así que los datos reales tenían que estar llegando a la tabla que le pasé como parámetro, no en lo que yo estaba leyendo. Ya lo corregí para leer el lugar correcto.

**Cómo probar:**

1. Alimentá cualquier Pal con el menú radial (cualquiera sirve).
2. Avisame y reviso el log — si esta vez aparecen datos reales de tu comida (nombres de items, cantidades), ya podemos pasar a la siguiente etapa (encontrar el item exacto para poder gastarlo de verdad). Si sigue vacío, tendría que buscar un camino distinto y más directo para leer tu inventario.

## Continuación 81 (2026-09-03): ¡funcionó! ya podemos leer tu comida real, y una cuarta confirmación de la diferencia Otomo/trabajador

**Contexto:** repetiste la prueba una vez más (Daedream salvaje, Foxparks tu Otomo, Lamball como trabajador).

**Buenas noticias:**

1. Cuarta especie distinta (Lamball esta vez) confirmando que los Pals trabajadores de base disparan la función real de alimentar, y tu Otomo activo otra vez no. Ya con cuatro pruebas separadas mostrando exactamente lo mismo, esto es un hecho confirmado del juego, no una casualidad.

2. **El arreglo del diagnóstico de comida funcionó de verdad** — el log mostró dos items reales en tu inventario. Antes de este pase solo veíamos "punteros" sin información útil; ahora ya sé que la corrección apuntaba al lugar correcto. Ajusté el código una vez más para que, en vez de solo confirmar "hay 2 items", te diga el NOMBRE real del item y la cantidad. Todavía no vi ese resultado final en un log (lo acabo de corregir), así que necesito una prueba más para confirmar que muestra los nombres reales.

**Cómo probar:**

1. Alimentá cualquier Pal con el menú radial (cualquiera sirve, no hace falta repetir los 3 tipos esta vez a menos que quieras).
2. Avisame y reviso el log — si ahora aparecen nombres reales de items de comida con sus cantidades, la Etapa 1 de esta feature queda terminada y pasamos a la Etapa 2 (encontrar la forma de gastar ese item de verdad).

## Continuación 82 (2026-09-03): los nombres de los items siguen sin aparecer — mejoré el diagnóstico para ver el error real

**Contexto:** alimentaste a varios Lamballs salvajes seguidos con el menú radial (gracias por las instrucciones claras que te di la vez pasada, funcionaron bien). El inventario nunca se abrió para vos — eso es normal y esperado, un Pal salvaje alimentado con nuestro mod no abre inventario todavía, esa parte no cambió.

**Lo que encontré:** el diagnóstico sigue viendo 2 items reales en tu inventario (eso sigue funcionando), pero cuando intento leer el NOMBRE y la CANTIDAD de cada uno, me sigue dando "nada" (nil) las 6 veces que probaste. El problema es que mi código anterior escondía el motivo real del fallo — no podía distinguir entre "el campo está vacío de verdad" y "estoy leyendo el campo de la forma incorrecta". Ya arreglé eso para que el log me muestre el error exacto si lo hay, en vez de esconderlo.

**Importante:** esto sigue siendo solo diagnóstico de lectura, nada cambió en cómo alimentar funciona.

**Cómo probar:**

1. Alimentá un Pal salvaje una vez más con el menú radial (con uno alcanza).
2. Avisame y reviso el log. Esta vez, si hay un error real, lo voy a poder ver clarito y sabré exactamente qué corregir. Si sigue sin error pero sin datos, significa que el problema es distinto de lo que pensaba y voy a tener que buscar por otro lado.

## Continuación 83 (2026-09-03): fui a revisar los archivos del juego directamente y encontré algo prometedor sobre las "kinship peaches"

**Contexto:** tenías toda la razón en dos cosas: (1) que el inventario nunca se abra para un Pal salvaje no es un bug, es simplemente una parte de la feature que todavía no construimos; y (2) en vez de seguir adivinando la sintaxis del código, fui directo a revisar los archivos reales del juego, como pediste.

**Lo que encontré:** abrí el archivo interno del juego que contiene la tabla maestra de todos los items (usando una herramienta que ya habíamos usado antes en este proyecto para investigar otras cosas) y encontré los nombres reales que el juego usa internamente para varios alimentos: carne cruda, bayas rojas, leche, miel, huevo, etc.

Pero lo más interesante: encontré dos items llamados literalmente **"AffectionFruit_01" y "AffectionFruit_02"** ("Affection" = cariño/afecto). Esto encaja perfecto con la categoría especial de items "para dar puntos de amistad" que ya habíamos encontrado antes en los datos del juego. Es una pista muy fuerte de que esto es exactamente lo que vos llamabas "kinship peaches" — y ya existen en el juego, no hay que inventarlos.

**Importante:** todavía no está 100% confirmado que esos nombres sean exactamente los que el juego usa cuando le preguntamos "¿cuánto tenés de esto en tu inventario?" — son nombres que aparecen en los archivos, pero falta la prueba en vivo. Por eso, en vez de seguir insistiendo con el método que no funcionaba, agregué una forma mucho más simple de preguntar: en vez de pedirle al juego "dame TODA tu comida de una vez" (que es lo que fallaba), ahora le pregunto uno por uno "¿cuánto tenés de ESTE item específico?" para cada nombre real que encontré.

**Cómo probar:**

1. Andá con algunos de estos items en tu inventario si podés (carne, bayas, huevo, leche, miel — lo que tengas a mano).
2. Alimentá un Pal salvaje con el menú radial.
3. Avisame y reviso el log — si los números coinciden con lo que realmente tenés, ya tenemos confirmado el nombre correcto y podemos avanzar a la siguiente etapa de verdad.

## Continuación 84 (2026-09-03): SE ROMPIÓ EL JUEGO - ya está arreglado, pero quiero que sepas exactamente qué pasó

**Lo que pasó:** el diagnóstico nuevo que agregué la vez pasada (el que preguntaba "¿cuánto tenés de este item?" uno por uno) hizo que el juego se cerrara de golpe, dos veces seguidas. Esto es serio y quiero ser directo al respecto: fue un error mío. Probé una función del juego que nunca habíamos usado de esa forma exacta antes (pasarle un nombre de item como texto, en vez de leerlo de un objeto que ya existe), y resultó ser peligrosa — algo que no había pasado en los ~111 pases anteriores de este proyecto.

**Ya está arreglado:** saqué por completo ese diagnóstico del camino real de "alimentar" (F9/F10 y el menú radial). Alimentar a un Pal ahora funciona exactamente igual que antes de que empezáramos con el tema de la comida real — sin ningún código nuevo corriendo de fondo que pueda volver a romper algo.

**Por qué pasó (para que quede documentado):** las veces anteriores que "adiviné" cómo llamar a una función del juego sin estar 100% seguro, si me equivocaba, el peor caso era que apareciera un error en el log y ya — nunca se rompía el juego. Esta vez fue distinto: la función que probé, al recibir el nombre del item de una forma que el juego no esperaba, hizo que intentara leer memoria que no existía, y eso sí puede tirar abajo el juego entero, sin que nada de lo que yo escriba en el código pueda evitarlo después de que ya se mandó mal. Fue una lección real: de ahora en adelante voy a ser mucho más cuidadoso antes de probar en vivo cualquier función que necesite que le arme un dato desde cero (en vez de solo leer un dato que el juego ya tiene).

**Cómo probar:**

1. Alimentá cualquier Pal como siempre — con el menú radial, o con F9/F10 si querés.
2. Debería funcionar exactamente igual que veníamos probando, sin crashes.

**Sobre la feature de comida real:** queda pausada por ahora en la Etapa 1 (ya sabemos algunos nombres reales de items, incluyendo "AffectionFruit_01/02" que probablemente son las kinship peaches) pero sin terminar de confirmar. La vamos a retomar con mucho más cuidado más adelante, o podemos pasar a otra cosa de tu lista si preferís — vos decidís.

Perdón por el susto, y gracias por avisarme enseguida con el detalle del crash — eso es justo lo que necesitaba para diagnosticarlo rápido y arreglarlo sin tener que adivinar de nuevo.

## Continuación 85 (2026-09-03): el JSON de las berries no sirvio directamente, pero encontre algo mejor - y no requiere que toque codigo de nuevo

Dragon: el archivo que volcaste buscando "berries" (T_itemicon_Food_Berries.json) resulto ser solo el icono/imagen del item en el inventario, no el dato real de cuantas tenes o donde estan guardadas. No es un fallo tuyo ni fue tiempo perdido - confirma que el nombre del icono incluye "Food_Berries", pero no es lo que necesitamos.

Buscando en los archivos del juego encontre algo mejor: existe un objeto real llamado UPalItemSlot que representa cada "casillero" real de tu inventario mientras jugas (uno por cada espacio que tiene un item adentro). Ese objeto tiene adentro exactamente los datos que necesito: en que casillero esta, el ID del contenedor (tu inventario), que item es, y cuantos tenes. Si lo encontras y lo volcas con Live View, como ya hiciste antes, no tengo que tocar ni una linea de codigo Lua para conseguir esta info - cero riesgo de otro crash como el anterior.

Pasos, bien especificos:

1. Anda a tu inventario real (el del jugador, no el de un Pal) y fijate cuantas Berries (o cualquier otro item de comida) tenes exactamente. Anota ese numero - lo vamos a usar para confirmar que encontramos el casillero correcto.
2. Abri Live View, igual que la vez pasada.
3. En la busqueda, escribi: PalItemSlot
4. Es probable que aparezcan VARIOS resultados (uno por cada casillero de tu inventario que tiene algo adentro) - no busques a mano cual es cual, no hay forma de saberlo mirando el nombre.
5. Volca ("Dump as JSON") los primeros 15 a 20 resultados de esa lista (los que aparezcan primero esta bien, no hace falta que sean todos).
6. Contame cuantos volcaste en total y avisame cuando este listo - yo los reviso todos del lado mio y busco el que tenga el mismo numero que anotaste en el paso 1.

No hace falta que sepas cual es el correcto vos mismo, ni que entiendas el contenido del JSON - eso lo reviso yo. Solo necesito que vuelques varios y me digas el numero real que anotaste en el paso 1 para poder comparar.


## Continuación 86 (2026-09-03): revise TODOS los JSON que ya habias generado (no hacia falta que buscaras mas) - y encontre algo importante que cambia el plan

Buenas noticias y una correccion importante, ambas de los mismos archivos.

Resulta que UE4SS ya estaba guardando en tu disco, en la carpeta `ue4ss/IndividualObjectDumps/`, cada "Dump as JSON" que hiciste en tus ultimas dos sesiones de prueba - no hacia falta que me pasaras nada a mano, pude leerlos directo desde tu compu. Ahi encontre 5 dumps reales de `PalItemSlot` (con SkillCards, dinero, etc.) que confirman con numeros reales exactamente la forma que necesitabamos: cada slot tiene su `ContainerId` (un codigo largo), su `ItemId.StaticId` (el nombre real del item, ej. "Money"), y su `StackCount` (cuantos hay) - el slot de dinero mostraba 856, un numero bien realista, buena señal de que la lectura es correcta.

Pero al revisar tu log de esa misma sesion, vi que alimentaste a tu Otomo (Kitsunebi) tres veces reales por el menu radial normal del juego - y el hook que instale hace varias pasadas (pensado para "escuchar" exactamente ese momento) nunca se disparo ni una vez en esas tres alimentadas. Eso normalmente seria mala noticia, pero en este caso es informacion util: significa que alimentar a un Otomo por el menu normal NO usa la funcion que yo pensaba. Revisando otros JSON que dumpeaste esa sesion (unos objetos con nombres como "ActionPair_FeedItem"), encontre el mecanismo real: es un sistema mucho mas armado, con animaciones, camara, y coordinacion entre tu personaje y el Otomo - no una sola función simple como pensaba antes.

Esto es un cambio real de plan para la funcion de "que el Pal salvaje coma comida real de tu inventario" - es mas complicado de lo que pensaba hace un par de pasadas. Antes de escribir mas codigo para esto, prefiero pensarlo bien (y probablemente conversarlo contigo) en vez de tirar una solucion a medias.

De yapa: encontre que el menu radial de "Worker" (el que usas para Pals de base) SI trae de forma directa y simple cual Pal fue seleccionado y si fue Pet o Feed - podria simplificar el sistema que ya tenemos funcionando, pero no es urgente porque lo actual ya anda bien.

Tambien, como me pediste, borre todos los JSON viejos de `ue4ss/IndividualObjectDumps/` (ya los lei y guarde lo importante en los docs) y un archivo de crash viejo y vacio que quedaba de un bug ya arreglado hace tiempo - pediste permiso para borrar y me lo diste, asi que quedo limpio para la proxima vez que uses Live View.

No hay nada nuevo para probar todavia de tu parte - esto fue puramente revisar lo que ya tenia guardado.


## Continuación 87 (2026-09-03): agregue un nuevo "oido" (100% seguro, no hace nada por si solo) para intentar encontrar la funcion real que gasta la comida

Con lo que encontre antes (que alimentar al Otomo no usa la funcion que yo pensaba), busque en la lista de funciones del objeto "slot" (el que representa cada casillero del inventario) y encontre una que se llama literalmente "usar esto en un personaje" (`RequestUseToCharacter`). Es una funcion que vive DENTRO del mismo objeto que ya tiene la comida adentro - eso es importante porque significa que si funciona, no tengo que "inventar" ningun dato nuevo, solo usar objetos que ya existen en el juego. Es mucho mas seguro que lo que causo el crash hace unas pasadas.

Por ahora SOLO agregue un "oido" - no hace nada, solo escucha si el juego llama a esa funcion y anota los datos si pasa. Cero riesgo, no toca nada, no puede romper nada.

**Que hacer en tu proxima sesion (nada especial, solo jugar normal):**

1. Anda a tu base o donde tengas a tu Otomo activo.
2. Alimentalo por el menu radial de siempre (el "4"), como ya hiciste antes - no hace falta nada distinto a lo que ya hiciste.
3. Segui jugando un rato normal, no hace falta hacer nada mas especifico.
4. Cuando quieras, mandame el log (o decime que ya jugaste) y yo reviso si aparecio una linea que dice "[SLOT-USE-DIAG]" - si aparece, es una gran pista; si no aparece, tambien sirve porque descarta esa opcion.

No hace falta que hagas nada con Live View esta vez - el log del juego solo (`UE4SS.log`) alcanza.


## Continuación 88 (2026-09-03): FUNCIONO - encontramos la funcion real que gasta la comida

Buenisima noticia. Alimentaste a tu Otomo y el "oido" que instale la vez pasada escucho exactamente lo que necesitabamos, tres veces: cada vez que alimentaste, el numero de items en ese casillero bajo de a uno (65, despues 64, despues 63). Eso confirma, con datos reales y no con una suposicion, que encontramos la funcion de verdad que el juego usa para gastar comida.

Lo unico que fallo fue puramente cosmetico: en vez de mostrar el nombre real del item (por ejemplo "BerryRed"), el log mostraba una direccion de memoria fea tipo "FNameUserdata: 0000...". Ya lo arregle - era solo un detalle de como le pido a Lua que convierta esos datos a texto legible, nada relacionado a seguridad ni riesgo.

**Que hacer ahora:** exactamente lo mismo que la vez pasada - alimenta a tu Otomo una vez mas por el menu radial de siempre. No hace falta nada especial ni distinto. Con esta correccion, la proxima vez el log deberia mostrar el nombre real de la comida que usaste en texto normal, en vez de esa direccion rara. Avisame cuando lo hagas y reviso el resultado.


## Continuación 89 (2026-09-03): confirmado el nombre real ("Berries") - y agregue una tecla nueva de PRUEBA (CTRL+J) que todavia NO gasta nada

El log mostro clarito: `ItemId.StaticId=Berries` - ese es el nombre real que usa el juego para las bayas. Con esto y lo de la pasada anterior, ya tengo entendido (en teoria) todo lo necesario para hacer que un Pal salvaje coma comida real de tu inventario.

Pero antes de probar eso de verdad (que SI gastaria un item real de tu inventario, no como todo lo que veniamos haciendo que solo escuchaba sin tocar nada), agregue una tecla nueva SOLO para probar en modo "simulacro": CTRL+J. Esta tecla no gasta nada, no alimenta a nadie, solo mira y anota en el log.

**Que hacer en tu proxima sesion (importante, seguí los pasos en orden):**

1. Antes de nada, anda a tu inventario y anota cuantas Berries (bayas) tenes exactamente en este momento. Ese numero es importante para el paso 4.
2. Apunta con la camara a CUALQUIER Pal (puede ser salvaje o el tuyo, no importa cual).
3. Con la camara apuntando, presiona CTRL+J (control y J juntos).
4. Revisa que el juego no se haya trabado ni pasado nada raro (no deberia, es de solo lectura) - y si podes, decime el numero que anotaste en el paso 1, para comparar con lo que aparezca en el log.
5. Repetilo un par de veces mas si queres, apuntando a Pals distintos - cuantas mas pruebas, mejor.

No hace falta que hagas F9, F10, ni el menu radial esta vez - esto es completamente aparte, una prueba nueva e independiente.


## Continuación 90 (2026-09-03): IMPORTANTE - la tecla CTRL+J ya NO es un simulacro, ahora SI gasta comida de verdad

Tu numero (62 bayas) coincidio EXACTO con lo que encontro el simulacro. Esa fue la confirmacion que necesitaba, asi que actualice la tecla CTRL+J: antes solo miraba y anotaba, ahora hace la accion real.

**MUY IMPORTANTE antes de probar:** la proxima vez que presiones CTRL+J apuntando a un Pal, el mod va a:
- Gastar 1 baya real de tu inventario (de tu monton mas grande de bayas, se identifica solo).
- Intentar "alimentar" de verdad al Pal que estes mirando (salvaje o tuyo, cualquiera).

No deberia romper nada (ya probamos cada pieza por separado y todas funcionaron bien), pero es la primera vez que el mod hace una accion real con esta funcion nueva, asi que quiero que lo sepas antes de tocarla.

**Que hacer:**

1. Asegurate de tener al menos 1 baya en el inventario (ya deberias, tenias 62).
2. Apunta a cualquier Pal (probá primero con uno salvaje, para ver si funciona incluso en los que no son tuyos - esa es la idea final de todo esto).
3. Presiona CTRL+J una sola vez.
4. Fijate si el juego se comporta raro (animacion rara, se traba, algo visual). Si pasa algo raro, avisame altiro y dejamos de usar esa tecla hasta revisar.
5. Fijate en tu inventario si bajaron las bayas (de 62 a 61, por ejemplo).
6. Fijate si el Pal muestra algun cambio (aunque sea minimo, como una animacion de comer, o un cambio de confianza si es un Pal salvaje).
7. Avisame el resultado (bajo el numero de bayas? paso algo con el Pal? algo raro?) y reviso el log.


## Continuación 91 (2026-09-03): encontre por que "no era confiable" - y ahora la prueba hace el ciclo completo (come + reacciona feliz)

Tenias toda la razon en que no era confiable, y revisando el log linea por linea encontre exactamente por que - no es al azar, es bien clarito:

- Cuando apuntaste a un Pal SALVAJE (un pollo), la funcion "dijo que si" pero en realidad no hizo nada - no bajo ninguna baya.
- Cuando apuntaste a TU OTOMO activo (el que llevas contigo), SI funciono las dos veces, bajando una baya cada vez.

O sea: la funcion que encontramos solo funciona con tu propio Otomo activo, no con cualquier Pal. Es una restriccion interna del juego que no podiamos ver antes de probarlo en vivo - por eso valio la pena hacer la prueba.

En vez de pelear para "engañar" esa restriccion, le agregue algo mas simple: si la funcion del juego no bajo el numero, el mod ahora lo baja el mismo directamente (como una anotacion manual, mucho mas simple y segura que llamar a una funcion del juego). Ademas, ahora despues de comer, el Pal reacciona feliz automaticamente (la misma reaccion que ya usamos en el Feed normal) - eso es lo que realmente le da confianza real, no solo gastar el item.

**Que hacer en tu proxima sesion:**

1. Apunta especificamente a un Pal SALVAJE esta vez (el caso que fallaba antes).
2. Presiona CTRL+J una sola vez.
3. Fijate si: (a) bajo una baya de tu inventario, (b) el Pal hizo alguna animacion de reaccion feliz, (c) haya pasado algo raro o el juego se traba.
4. Repetilo en tu Otomo tambien, para comparar.
5. Avisame que viste y reviso el log con detalle.


## Continuación 92 (2026-09-03): PAUSA - me corregiste el enfoque, hicimos una prueba real, y encontramos que el problema es mas profundo de lo que pensaba. Quedamos esperando tu decision.

Esto quedo pausado a proposito, asi que lo documento bien detallado para que no se pierda nada.

**Lo que paso:** te propuse (mal) que el mod eligiera automaticamente las bayas y las gastara solo, sin mostrar ningun menu - una especie de "truco" por atras. Me corregiste altiro, y con toda razon: el juego de verdad abre tu inventario real cuando alimentas, te deja elegir (o te muestra que no tenes nada si estas sin comida), nunca elige por vos ni te bloquea. Tu instruccion fue clara: no inventar un truco nuevo, encontrar como lo hace el juego de verdad y activar ESO para nuestra interaccion de alimentar.

Esto tiene mucho sentido y ademas es exactamente como se construyo TODO lo demas en este mod (el menu "4", el Pet/Feed en pals salvajes, etc.) - siempre buscando el sistema real del juego y activandolo, nunca inventando un reemplazo.

**La pregunta que surgio:** el mod YA tiene un truco (desde hace bastantes pasadas) que hace que un Pal salvaje "aparente" ser tu Otomo activo mientras el menu esta abierto - asi es como Pet/Feed ya funcionan hoy en pals salvajes. La pregunta era: ¿ese mismo truco alcanza para que el sistema REAL de comida (el que abre tu inventario de verdad) tambien se active solo, sin que tengamos que hacer nada nuevo?

**La prueba que hicimos:** Elegiste "Feed" en el menu radial real, apuntando a pals salvajes, 6 veces seguidas. Revise el log linea por linea.

**El resultado:** No. El truco actual NO alcanza. En las 6 veces, solo se disparo nuestra propia animacion simplificada (la que ya teniamos) - CERO señales del sistema real de inventario/comida (el mismo que SI se activa cuando alimentas a tu Otomo real). Osea, el juego mismo decide no activar el sistema real cuando el Pal solo esta "disfrazado" de Otomo en ese unico lugar donde lo revisamos - debe haber una verificacion mas profunda en otro lado, que probablemente chequea si el Pal esta REALMENTE registrado como tuyo (no solo aparentandolo), en algun lugar mas "oficial" del juego.

**Por que esto importa:** satisfacer esa verificacion mas profunda probablemente signifACaria tocar un registro real de "a quien pertenece este Pal" - algo bastante mas delicado que todo lo que tocamos hasta ahora (que siempre fue leer datos o escribir un numero simple). No se si eso es posible de hacer de forma segura todavia.

**Donde quedamos:** parado aca, a proposito, esperando que decidas si querés que siga investigando esa verificacion mas profunda (mas trabajo, mas incierto, capaz mas riesgoso) o si preferis repensar la prioridad de esta funcion por ahora. No hay nada que probar de tu lado en este momento - esto es una decision de diseño, no una prueba tecnica.

**Nota tecnica para no perderla**: la tecla CTRL+J (el "truco" de auto-elegir bayas) sigue en el codigo tal cual quedo, pero ya sabemos que NO es el diseño final - se queda ahi solo como evidencia de que la funcion de gastar comida (RequestUseToCharacter + el respaldo manual) funciona tecnicamente, por si sirve mas adelante una vez que encontremos como activar el sistema real.


## Continuación 93 (2026-09-03): investigación pedida por Dragón — ¿qué pasamos por alto?, y hacia dónde ir ahora

Dragón pidió una revisión de fondo: revisar los otros mods de referencia y el propio proceso de este proyecto en busca de algo que se haya pasado por alto o hecho mal, y una recomendación real de cómo seguir — dejando el método (archivos, internet, Live View) a mi criterio.

**Lo que se hizo:** en vez de releer los mods de referencia superficialmente otra vez, fui directo al propio `Pal.hpp` (el volcado real de headers, ya en el disco de Dragón bajo la instalación del juego — `Pal/Binaries/Win64/ue4ss/CXXHeaderDump/Pal.hpp`, nunca copiado a este proyecto) y leí el código fuente real de `Interaction.lua`/`Capture.lua` de punta a punta, en vez de confiar solo en el resumen de este archivo.

**Hallazgo 1 — por qué la sustitución de `TryGetSpawnedOtomo` nunca iba a alcanzar el sistema real de comida.** El cuerpo completo de la clase `UPalOtomoHolderComponentBase` (ahora confirmado, campo por campo) NO tiene ningún campo simple tipo "OtomoActivo" — `TryGetSpawnedOtomo()` es una función que calcula su respuesta cada vez que se llama (probablemente resolviendo `CharacterContainer` + algún índice), no un getter de un valor guardado. Nuestra sustitución (`ReturnValue:set()`) solo engaña a quien LLAMA a esa función puntual — nunca puede alcanzar a cualquier otro sistema del juego que resuelva "cuál es mi Otomo" por un camino distinto. Y el sistema real de comida (`UPalAction_FeedItemToCharacter`, confirmado en el header dump) NO es una función simple — es un objeto de acción completo (mismo patrón que `UPalAIActionComponent`/`UPawnActionsComponent`, la MISMA familia de sistema que el seguimiento real de Otomo que la Continuación 62 ya había encontrado y dejado pendiente). Nada indica que este sistema de acciones lea `TryGetSpawnedOtomo` para nada — probablemente recibe su objetivo por otro camino directo (quién sabe cuál, todavía sin confirmar).

**Hallazgo 2 — una función paralela, nunca investigada, que podría ser el camino real.** En la misma clase existe un segundo sistema de "selección" completamente separado y jamás tocado por este proyecto: `TryGetCurrentSelectPalActor()` / `IsValidCurrentSelectPalActor()` / `SetSelectOtomoID(_Internal/_ToServer/_ToALL)`. Es un candidato real para "a quién se dirige la acción real", nunca antes considerado porque toda la investigación se concentró en `TryGetSpawnedOtomo`.

**Hallazgo 3 — confirmación de que un Pal salvaje SÍ tiene la pieza estructural que hace falta para el seguimiento real.** La Continuación 62 dejó pendiente sin confirmar si el controlador de un Pal salvaje tiene un `AIActionComponent` utilizable. Ahora confirmado por lectura directa del header dump: el campo `AIActionComponent` y la función `GetAIActionComponent()` están declarados en la clase BASE `APalAIController` (línea 9381/9424 de Pal.hpp) — la misma clase base que meses atrás ya se había confirmado que comparten los controladores de Pals salvajes Y de Otomo (`BP_MonsterAIController_Otomo` extiende esa misma base). Es decir: estructuralmente, todo Pal salvaje YA tiene este componente — lo que sigue sin confirmar es si en tiempo real está POBLADO/usable para un Pal cuya IA corre en modo "salvaje" (Continuación 62's `[FOLLOW-DIAG]` sigue siendo la prueba pendiente para eso, ahora con mucho más respaldo de que va a salir positivo).

**Sobre los mods de referencia:** no se encontró nada nuevo — `RemoteAccessEverything` y `Pal Analyzer` siguen siendo, como ya se había confirmado antes, ajenos a este problema específico (acceso remoto a cajas, e inspección genérica de objetos, respectivamente), y no se invirtió tiempo extra re-abriendo sus .pak porque las sesiones anteriores ya los caracterizaron con evidencia real. Se intentó releer `PassiveWildPals` (el Blueprint de IA salvaje ya extraído) para buscar directamente si referencia `AIActionComponent`, pero las herramientas de extracción de texto disponibles en este entorno no lograron sacar contenido legible de ese archivo binario en particular (no hay un `strings` real instalado aquí) — no es un resultado negativo, es una limitación de herramienta, y no valió la pena perseguirlo más allá dado que el Hallazgo 3 ya responde la misma pregunta por otra vía (el header dump nativo, más confiable que un Blueprint compilado de todos modos).

**Investigación externa:** se confirmó (GitHub, UE4SS-RE/RE-UE4SS) que overridear el valor de retorno de una función ya hookeada tiene antecedentes de bugs conocidos en versiones pasadas de UE4SS para funciones Blueprint — contexto útil, pero no parece ser la causa aquí (esta pasada nunca falló en leer/sobreescribir el valor, 474/474 en la Continuación 84). No se encontró ningún mod público ni documentación que ya resuelva "hacer que un Pal salvaje reciba comida/seguimiento real" — confirma, otra vez, que esto sigue siendo territorio genuinamente sin explorar públicamente.

**Recomendación dada a Dragón, pendiente de su decisión:**
1. Paso inmediato, bajo riesgo, solo observación: agregar hooks de lectura sobre `TryGetCurrentSelectPalActor`/`IsValidCurrentSelectPalActor`/`SetSelectOtomoID*` para ver en un log real si el sistema de comida (o el de seguimiento) pasa por ahí en vez de por `TryGetSpawnedOtomo`.
2. Paso más grande, alineado con la filosofía real de este proyecto ("activar el sistema real, no fingirlo"), pero de una categoría de riesgo nueva (construir/empujar objetos de acción de IA reales, no solo leer o redirigir un puntero): retomar el `[FOLLOW-DIAG]` pendiente desde la Continuación 62 para confirmar en vivo si el `AIActionComponent` de un Pal salvaje está realmente poblado, y si es así, evaluar empujar la acción real de comida/seguimiento sobre ÉL en vez de seguir peleando con getters. Esto uniría los dos problemas pendientes (seguimiento real, comida real) en un solo mecanismo real, en vez de dos hacks separados — pero merece luz verde explícita de Dragón antes de intentarse, como toda categoría de riesgo nueva en este proyecto.

Sin cambios de código esta pasada — es investigación pura, esperando la decisión de Dragón sobre cuál de los dos pasos (o ambos) seguir.

## Continuación 94 (2026-09-03): la herramienta que faltaba, un desfase de archivos real encontrado y arreglado, y dos hooks nuevos ya en el juego

Dragón pidió avanzar con el paso seguro propuesto en la Continuación 93, y además encontrar o reinstalar las herramientas que la sesión anterior usó para leer los mods de referencia (confirmó que sí existían en este dispositivo antes).

**Herramienta recuperada:** `repak` (usado en todo este proyecto para leer los `.pak` de los mods de referencia) había quedado instalado en un entorno separado y efímero de una sesión anterior que no persiste — por eso ya no estaba. Se descargó de nuevo (misma versión v0.2.3, sin instalador) a `Proyectos\_tools\repak\`, junto al resto de herramientas compartidas del workspace. Con esto se pudieron leer por fin los dos mods de referencia que nunca se habían guardado localmente (`RemoteAccessEverything`, `Pal Analyzer`) — ya extraídos en `palbonds-mod\research\unpacked\` para no tener que repetir esto en el futuro.

**Un desfase real de archivos, encontrado antes de que causara daño:** el mod y su documentación viven en tres lugares — la carpeta real del juego, un espejo en la raíz de `32-PalBonds\` (`mod\`, `docs\`, `DESIGN.md`), y un segundo espejo anidado que sigue el layout documentado del propio proyecto (`32-PalBonds\palbonds-mod\...`). En algún momento reciente, los cambios empezaron a guardarse solo en el espejo de la raíz y en el juego real, mientras el espejo anidado dejó de actualizarse silenciosamente para `Interaction.lua`, `Logger.lua`, `Personality.lua`, `DESIGN.md` y `hook-points.md` — hasta ~120 pasadas y unas 40 entradas de este mismo archivo de diferencia en el peor caso. Se encontró ANTES de editar nada encima de esa versión vieja, comparando los tres lugares archivo por archivo. Ya resincronizado. **Queda pendiente una decisión de Dragón**: hay dos carpetas de espejo con nombres confusamente parecidos (`32-PalBonds\mod\` vs `32-PalBonds\palbonds-mod\mod\`) — vale la pena decidir cuál conservar y borrar la otra para que esto no vuelva a pasar. No se borró nada por cuenta propia.

**Corrección real sobre la pasada anterior:** el candidato principal que la Continuación 92/pasada-120 había propuesto para el "chequeo profundo de propiedad" (`OtomoIndividualIdList`) resultó pertenecer a una estructura exclusiva del modo Arena/PvP, no a nada que se lea durante el juego normal — el mismo tipo de error que este proyecto ya había cometido y corregido una vez antes (con `GetOtomoHolder`). Se descarta como pista.

**Candidato mejor encontrado en su lugar:** `UPalPlayerPartyPalHolder` (la misma clase real ya confirmada desde la sexta continuación, con `FirstOtomoPal`/`SecondOtomoPal`/`BenchMember`) tiene una función nunca antes vista, `PawnOtmoIsPartyOtomo(bool, handle)` — una consulta booleana que recibe un handle directamente y pregunta exactamente "¿este handle es realmente mi Otomo de party?". Es el candidato más fuerte encontrado hasta ahora para el chequeo profundo. Solo se agregó una LECTURA de esta función (nunca una escritura) — se dispara una sola vez por cada Pal salvaje nuevo que se sustituye en el menú (no por tick), buscando instancias vivas de esa clase y preguntándole si el handle del Pal salvaje sustituido ya cuenta como su Otomo real (se espera que diga que no — la confirmación real vendría de comparar contra tu Otomo de verdad, todavía no probado).

**Dos hooks nuevos, de solo observación, agregados al juego:** `OpenOtomoFeedInventory` y `SelectedFeed`, dos funciones nativas reales (confirmadas en el volcado de headers) que nunca se habían enganchado — la primera ya se había anotado como pista desde hace muchísimas pasadas pero nunca se probó. Ambas puramente de observación, mismo criterio de siempre.

Nada de esto escribe sobre ningún estado real del juego — todo es lectura o observación. Verificado con `luaparse` (tampoco había un `luac` real disponible en este dispositivo — mismo problema de herramienta faltante que con `repak` — se usó como sustituto de solo sintaxis). Desplegado en los tres lugares (juego real + los dos espejos, ya resincronizados).

**Prueba pendiente para Dragón:** apuntar el menú "4" real a un Pal salvaje y elegir Alimentar una vez, igual que en la Continuación 92. Revisar el log por líneas `[FOOD-DIAG]` (para `OpenOtomoFeedInventory`/`SelectedFeed`) y `[PARTY-DIAG]` (el resultado real de `PawnOtmoIsPartyOtomo` sobre el Pal salvaje sustituido). Sigue sin haber nada que llamar o escribir de verdad — solo confirmar si esta es la pista correcta antes de considerar cualquier paso más arriesgado.

## Continuación 95 (2026-09-03): resultado real de la prueba — el chequeo profundo es más angosto de lo pensado, y la carpeta duplicada ya quedó consolidada

**Sobre la prueba de Dragón:** `PalPlayerPartyPalHolder` no llegó a existir ni una sola vez en esta sesión (0 instancias encontradas las tres veces) — no es un resultado negativo sobre la teoría en sí, simplemente no hubo ninguna instancia sobre la cual preguntarle nada; puede que esa clase solo exista en modo Arena, o que necesite otro disparador que esta sesión no tocó. Sin perseguir más por ahora.

**El hallazgo real:** `OpenOtomoFeedInventory` se disparó tanto para el Pal salvaje sustituido (dos veces) como para el Otomo real (una vez) — o sea, la decisión de intentar abrir el inventario NO depende de si es un Otomo de verdad. Pero `SelectedFeed` (la selección real de un item) solo se disparó UNA vez, y fue exactamente en el caso del Otomo real — nunca para el Pal salvaje. Esto angosta bastante el lugar del chequeo profundo: ya no está "en algún lugar entre la decisión y el picker", está adentro de `OpenOtomoFeedInventory` mismo (o en lo que llama internamente antes de que un item pueda seleccionarse de verdad). Como esa función no recibe ningún parámetro, tiene que estar leyendo algo interno — o vuelve a llamar `TryGetSpawnedOtomo` (y ahí nuestra sustitución debería alcanzar, lo cual sería raro que no funcione), o lee una variable que el propio menú ya cacheó antes (`SpawnedOtomo`, la variable real ya confirmada en el propio Blueprint del menú) en vez de llamar al getter de nuevo. Si es lo segundo, escribir esa variable directamente (no solo el valor de retorno del getter) sería el próximo experimento natural — no intentado todavía, es una escritura nueva sobre el estado del menú, así que quedó documentado como el siguiente paso concreto, no ejecutado sin avisar primero.

**Sobre la limpieza de carpetas:** confirmaste que el espejo anidado (`palbonds-mod/`) fue una decisión de la IA anterior, no algo que pediste — así que se consolidó todo en una sola carpeta plana bajo `32-PalBonds/`. Antes de borrar nada se encontró que el espejo de la raíz TAMBIÉN estaba incompleto (le faltaban 8 de los 11 scripts, un hueco que la Continuación 94 no había notado) — se corrigió copiando todo desde la carpeta real del juego, se movió lo que solo existía en el espejo anidado (`README.md`, `research/`, `docs/phase0-install.md`, `docs/phase1-research.md`, `enabled.txt`), y se verificó archivo por archivo antes de borrar la carpeta vieja. Ya vacía — solo falta que termine de borrarse la carpeta en sí, bloqueada por algo de Windows que la tiene abierta (sin ningún riesgo de pérdida, ya no tiene nada adentro). `DESIGN.md` y las referencias de `CLAUDE.md` ya se actualizaron para reflejar la carpeta plana.

## Continuación 96 (2026-09-03): implementado el experimento de escritura real — la variable cacheada del propio menú, no solo el getter

Dijiste que siguiera con el paso que había quedado planteado. Implementado: el mod ahora recuerda el widget real del menú (`WBP_PlayerRadialMenu_C`) apenas se abre, y además de la sustitución que ya existía sobre `TryGetSpawnedOtomo`, ahora también escribe directamente su propia variable cacheada (`SpawnedOtomo`) con el Pal salvaje sustituido — la misma idea que ya había funcionado antes con `IndividualHandle` para el menú de trabajador (escribir el campo real, no solo lo que lo envuelve). Es una categoría nueva de escritura para este proyecto (nunca se había escrito directo sobre el estado de un widget de menú), pero de bajo riesgo real: es estado de UI transitorio, no datos de guardado, y solo corre dentro de la misma ventana ya controlada de siempre (Pal salvaje confirmado, Otomo real excluido).

Verificado con `luaparse`, desplegado (carpeta real del juego + el único espejo que ya queda, `32-PalBonds/` plano).

**Prueba pendiente:** apuntar "4" a un Pal salvaje y elegir Alimentar, igual que antes. Revisar el log por `[RADIAL-REDIRECT-FIELD]` (si el campo existe y aceptó la escritura) y, la prueba real, si esta vez `SelectedFeed` sí se dispara para el Pal salvaje — eso confirmaría si esta era la pieza que faltaba.

## Continuación 97 (2026-09-03): la escritura funcionó, pero no era la pieza que faltaba — ya no queda ninguna palanca más "de superficie" para probar

Alimentaste a un Chikipi salvaje tres veces con el menú "4" real. La escritura sobre `SpawnedOtomo` funcionó de verdad las cuatro veces (cero errores) — pero `SelectedFeed` (una selección real de comida) siguió sin dispararse ni una sola vez. Solo nuestra propia aproximación (`[WILD-ACTION]`) actuó, igual que siempre.

**Esto descarta algo real, no es un callejón sin salida vacío:** este proyecto ya controla las dos cosas que un menú podría estar leyendo para saber "quién es mi Otomo" — la función (`TryGetSpawnedOtomo`) y la variable propia que el widget cachea (`SpawnedOtomo`). Las dos dicen "el Pal salvaje" durante toda la ventana, confirmado. El selector real de comida sigue sin abrirse. Eso significa que el chequeo real no lee ninguna de las dos — está preguntando algo más autoritativo, en algún registro real de "a quién pertenece este Pal", el mismo tipo de pregunta sin resolver desde hace meses en este proyecto (nunca se logró que `AddOtomoHandleToFreeSlot` ni nada parecido se dispare desde Lua, en ningún camino de captura real probado hasta ahora).

**No queda ninguna palanca más para probar sin cruzar a una categoría de riesgo más grande.** La aproximación actual (el gesto + Happy, ya conectado automáticamente al menú "4" real) sigue siendo el único camino que de verdad funciona para alimentar Pals salvajes — gana confianza real, con animación real, solo que sin gastar un item de verdad. Queda en tus manos: seguir empujando hacia el registro real de propiedad (más grande, más incierto, necesitaría mucho cuidado antes de cualquier prueba en vivo) o dar por buena la aproximación actual para esta función en particular y pasar a otra prioridad. Sin cambios de código esta pasada — es solo la lectura del resultado.

## Continuación 98 (2026-09-03): implementado "tímido → curioso", y qué encontré en los JSON que volcaste

**Sobre la lista de pendientes:** sí está — `DESIGN.md` §11 ("Feature wishlist"). Elegí "tímido → curioso tras una interacción exitosa" (tu idea original, de antes de que existiera el sistema de tiers) porque es autocontenida: se dispara desde un evento ya confirmado y confiable (acariciar/alimentar con éxito), sin depender del misterio de comida ni del scan de aplicación de personalidad que sigue sin confirmarse.

**Implementado:** la primera vez que acaricies/alimentes con éxito a un Pal cuya disposición registrada sea "tímido" (por tier forzado o por especie naturalmente tímida), pasa a "curioso" para siempre — se actualiza el estado registrado siempre, y además intenta (sin garantía) que esto se note en el comportamiento real de la IA, reutilizando la misma técnica ya seguro-probada del sistema de aplicación. Desplegado y verificado.

**Sobre los tres primeros JSON:** solo confirman rutas de función que ya teníamos (son volcados de METADATA de función, no de su implementación — las funciones nativas no tienen grafo de Blueprint que Live View pueda mostrar). No aportaron nada nuevo.

**El cuarto JSON sí fue valioso:** por primera vez se puede ver ADENTRO del grafo real de `BP_ActionPairBehavior_FeedItem_C` (la acción real de alimentar emparejada). Confirma que el objetivo/personaje de esa acción se lee de la ACCIÓN MISMA (no de ningún getter que podamos sustituir), y aparece una función nunca vista, `ReadPlayerFeedItemTo`, que probablemente resuelve qué item eligió el jugador. Pero esto no destraba nada nuevo: sigue sin verse qué dispara esta acción para un Pal salvaje en primer lugar — el mismo muro de siempre (el registro real de propiedad, nunca escribible desde Lua). Detalle completo en `hook-points.md`.

## Continuación 99 (2026-09-03): por qué no viste "WON-OVER" (no es bug), y dos funciones reales más confirmadas

**Sobre la prueba de personalidad:** revisé los 4 individuos que tiraron "tímido" esta sesión — ninguno llegó a ser realmente acariciado/alimentado, solo los vio el scan pasivo al pasar cerca. La función nunca tuvo oportunidad de dispararse — no está rota. La próxima prueba real necesita apuntar específicamente a un Pal cuyo log ya diga `disposition=skittish` y realmente interactuar con él.

**Los dos JSON nuevos sí aportaron algo real:** `ReadPlayerFeedItemTo` quedó confirmada en `/Script/Pal.PalPlayerUtility:ReadPlayerFeedItemTo` (una utilidad nativa, misma categoría que las que ya usamos con confianza). Y apareció una función que nunca habíamos visto, `"On Trigger Open Inventory Menu"`, en el listener principal de la HUD del juego — candidata real a estar un nivel ARRIBA de `OpenOtomoFeedInventory` en la cadena real. Agregué observación de solo lectura para ambas (cero riesgo), desplegado. Detalle completo en `hook-points.md`.

## Continuación 100 (2026-09-03): confirmado — el comportamiento visible no refleja la personalidad registrada, agregué una tecla para verla directamente

Revisé los 5 Pals que acariciaste esta sesión (2 Cattiva/PinkCat, 1 PlantSlime, 2 Daedream/DreamDemon) — todos parecían tímidos por cómo huían, pero el registro real dice: 4 salieron "curioso" y 1 "hostil". Ninguno era realmente tímido en nuestro sistema — lo que viste era el comportamiento normal de la IA salvaje, sin relación con la personalidad que le asignamos. Confirma justo lo que sospechabas: no se puede encontrar un Pal tímido mirando su comportamiento, porque la aplicación real (que la personalidad se note en el juego) sigue sin confirmarse.

**Agregué CTRL+P**: apuntá a cualquier Pal y presioná esa tecla — revisa el log por `[PERSONALITY-CHECK]` y te dice exactamente su disposición registrada, sin necesidad de acariciarlo/alimentarlo primero. Así podés buscar uno que diga "tímido" de verdad antes de gastar tiempo persiguiéndolo. Desplegado.

## Continuación 101 (2026-09-03): revisé la comida (sin novedad real), y desactivé el sorteo de personalidad como pediste

**Comida:** `ReadPlayerFeedItemTo` sí se disparó para TODAS las alimentadas de esta sesión, salvajes y reales por igual — no está bloqueada. Pero el hook que instalé solo captura los valores ANTES de que la función los llene (es un pre-hook simple, no post-hook), así que lo que vimos no dice nada nuevo todavía — haría falta un hook de antes+después como el que ya usamos en `TryGetSpawnedOtomo` para ver el resultado real. La única señal real sigue igual: `SelectedFeed` + el consumo real de item solo pasaron en las dos alimentadas a tu Otomo de verdad, nunca en las seis de Pals salvajes.

**Personalidad:** tenías razón, CTRL+P no sirve así — no es una herramienta práctica para leer en el momento. Hice lo que pediste: desactivé el sorteo de personalidad por ahora (`ENABLE_PERSONALITY_TIER_ROLL = false`). Con esto, la disposición registrada de cada Pal es directamente su valor real de especie — un Pal genuinamente tímido (según el juego, no un sorteo nuestro) es ahora exactamente el mismo que ves huir de verdad. Ya podés probar "tímido → curioso" contra la realidad: perseguí y acariciá/alimentá cualquier Pal que de verdad esté huyendo, sin necesidad de revisar nada antes. El sistema de sorteo queda intacto en el código, solo apagado — se puede reactivar cuando esto (e idealmente la aplicación real de personalidad) estén confirmados.

## Continuación 102 (2026-09-03): instalé Ghidra (investigación de fondo en curso), reescribí la aplicación real de personalidad con la técnica de un mod real, y un segundo mod revela el sistema real de seguidores secundarios

**Ghidra:** instalado (con Java 21 nuevo, el que ya había era muy viejo) y corriendo análisis real sobre el ejecutable del juego en este momento, en segundo plano — buscará específicamente las funciones de comida que nos faltan y avisaré apenas termine.

**Personalidad — reescrita de fondo, gracias al mod "Passive Pals" que encontraste.** Ese mod hace exactamente lo que necesitábamos, y lo hace mejor de lo que este proyecto había intentado nunca: nunca necesita un Pal "donante" cerca — cada preset de comportamiento tiene su propio objeto por defecto, alcanzable directamente sin ningún Pal vivo de por medio (el motivo real de por qué nunca encontrábamos un donante era una suposición equivocada, no falta de intentos). Reescribí `Personality.lua` completo con esta misma técnica real — ya no depende de que otro Pal de la especie correcta esté cerca. Reactivé el sorteo de personalidad (tenía que estar activo para que este arreglo se ponga a prueba de verdad). Desplegado, sin probar en vivo todavía — la prueba real: quedarte cerca de Pals salvajes y revisar el log por `[ENFORCE] SUCCESS`, después ir a ver a ESE Pal específico si de verdad actúa distinto.

**El otro mod que dejaste, "PalFollowerTweaks", no es para esto — es para otra cosa pendiente en la lista: el seguimiento real de Pals secundarios.** Confirma el nombre real del sistema detrás de Daedream/Dazzi/Flopie siguiendo sin ser tu Otomo principal (`PalFunnelCharacter`) — algo que este proyecto nunca había logrado nombrar con certeza. Quedó anotado en `DESIGN.md` como una pista real y prometedora para cuando se retome esa función — no lo toqué todavía, es un frente distinto del que estamos atascados.

## Continuación 103 (2026-09-03): implementado el mensaje real en pantalla cuando un Pal se une

El tercer mod que dejaste ("QuickConsumableSlots") tenía justo lo que preguntabas — un sistema real y ya probado para mostrar texto en pantalla (un "toast"). Lo implementé: ahora, cuando un Pal salvaje llega a confianza máxima y se une de verdad, aparece un mensaje real en pantalla ("A wild Pal has joined your party!" por ahora — texto genérico a propósito, no adiviné una función para sacar el nombre real de la especie ya que no la confirmamos todavía). Desplegado, sin probar en vivo — la prueba real es simplemente llegar a confianza máxima con un Pal salvaje (o usar la tecla de prueba F11/CTRL+K) y ver si aparece el aviso.

## Continuación 104 (2026-09-03): el mod más útil de toda la sesión — una función que dábamos por muerta resultó estar viva, y ya está implementado un experimento real para probarla

Este mod ("MultiPals", deja tener varios Pals activos a la vez) prueba algo grande: `ActivatePalByHandle` — una función cuyo nombre encontramos hace meses y que dimos por muerta después de ver que el cambio normal de Otomo nunca la llama — SÍ es real y SÍ funciona, solo que para otra cosa (activar un Pal EXTRA de tu equipo, no cambiar tu Otomo principal). Este mod solo la usa con Pals que ya son tuyos — nunca la probó con un Pal salvaje. Nada nos había impedido intentar eso antes, excepto no tener una llamada ya confirmada que funcione para probar.

**Ya implementé el experimento real**: una tecla nueva y aislada, CTRL+O, que apunta a un Pal salvaje y llama exactamente esta función con su handle real. Es información nueva y genuinamente prometedora — la pista más fuerte de todo este proyecto para la pregunta central que sigue sin resolver desde el principio: que un Pal salvaje realmente siga y ayude en combate como un Otomo de verdad.

**Riesgo real, explicado antes de que lo pruebes**: todo Pal que este mod activa ya estaba "guardado" (su actor no existe en el mundo hasta activarlo). Un Pal salvaje YA tiene su actor vivo caminando por ahí — nunca se probó esta función en ese caso. Mejor resultado posible: el juego toma control del actor que ya existe y empieza a comportarse como un Otomo real. Peor resultado posible (sin descartar): aparece una copia duplicada, o la función asume algo que nunca se preparó y se comporta mal de una forma que no podemos atrapar con pcall.

**Prueba pendiente, con cuidado**: guardá la partida primero, elegí un Pal salvaje común y de bajo valor, apuntale y presioná CTRL+O una sola vez. Fijate con atención: ¿el Pal original empezó a seguirte/ayudar como un Otomo real? ¿apareció una segunda copia? ¿no cambió nada?

## Continuación 105 (2026-09-03): revisé todo el log de la sesión de prueba — encontré y arreglé un lag real que yo mismo causé, y aclaré el resto

**El lag:** era mío, no de Ghidra. Al reescribir la aplicación de personalidad me olvidé de limitar un mensaje de error que ahora se repetía cada 8 segundos, para siempre, con cada Pal — 1170 líneas casi idénticas en tu sesión. Ya arreglado (una sola vez por Pal, como debía ser desde el principio).

**CTRL+O:** se disparó de verdad varias veces (confirmado en el log), sin errores — pero no tuvo ningún efecto visible. Es un resultado real y limpio: la función no hace nada con un Pal que nunca pasó por el registro real de propiedad, el mismo patrón que ya vimos con `RequestUseToCharacter`. Sí, además choca con el atajo de la consola — hay que cambiar esa tecla si retomamos esto.

**Tímido → curioso:** no fue un fracaso total. Sí pasó una vez de verdad — un Pal genuinamente tímido fue "ganado" con éxito (confirmado en el log) — pero el intento de cambiar su comportamiento real falló por el mismo motivo que el lag: no se pudo leer su componente de sensor. Los demás Pals que viste huyendo esta sesión nunca aparecieron como realmente tímidos en el registro — es comportamiento normal de la IA salvaje, no relacionado con nuestro sistema. (Y sí, "tímido"/skittish es el término correcto — no hay otro nombre para eso en el proyecto.)

**El mensaje al unirse:** funcionó exactamente como se diseñó — solo se dispara en la captura real por confianza, nunca en CTRL+K (esa tecla es a propósito un atajo que salta todo el sistema de confianza). No es un bug.

**Lo de que dejaron de seguirte tras la interacción 5:** no encontré ninguna evidencia de que esto se haya roto. Solo un Pal llegó a la interacción 5 en toda la sesión, y ESE sí empezó a seguirte correctamente (confirmado en el log) — y dejó de seguir después porque se capturó de verdad (eso es lo esperado, ya no hace falta fingir que sigue si ya es tuyo de verdad). No toqué Trust.lua ni Combat.lua en ningún momento de hoy.

Todo desplegado. Detalle completo en `hook-points.md`.

## Continuación 106 (2026-09-03): corrección sobre "skittish", limpieza de teclas, y Ghidra finalmente dio resultados reales

Dragón corrigió algo importante: "skittish" nunca fue un nombre real del juego — es una etiqueta interna de este mod (mapeada desde el preset real `BP_AIResponsePreset_Escape_to_Battle_C`, uno de ~10-11 presets reales confirmados en el `.pak` del juego junto a `Warlike`, `friendly`, `VillageNPC`, etc.). Dragón solo la usaba como su propio término para describir Pals que huyen, nunca como algo que el juego mismo llama así. Corregido en la documentación.

**Limpieza de teclas, a pedido explícito de Dragón** ("mantengan las teclas al mínimo, si necesitan una nueva, saquen o reemplacen una ya usada"). Se eliminaron CTRL+P (chequeo de personalidad — el propio Dragón ya lo había llamado poco práctico) y CTRL+O (el experimento de `ActivatePalByHandle` sobre un Pal salvaje — resultado negativo limpio confirmado, y además choca con la tecla de consola). Quedan: F9 (Acariciar), F10 (Alimentar), CTRL+K (captura directa sin esfera), CTRL+J (alimentar con item real). `InputSpy.lua` (~150 teclas) sigue aparte como herramienta temporal de investigación, no cuenta en este total.

**Ghidra por fin funcionó, después de tres intentos fallidos por problemas reales de la herramienta** (no por el contenido de la búsqueda — la lista de funciones buscadas siempre fueron los nombres reales ya confirmados por UE4SS, nunca "skittish" ni nada de personalidad). El script en Python (Jython) no podía correr porque Ghidra 12.x lo eliminó; la versión portada a Java chocó con el mismo error de compilación OSGi que un script propio de Ghidra ya había mostrado en el mismo análisis original (confirma que es un problema del entorno, no del código); instalar Python 3 portátil y ponerlo en el PATH tampoco alcanzó porque `analyzeHeadless.bat` nunca detecta Python así. La solución real: saltarse `analyzeHeadless.bat` por completo y usar el propio paquete Python de PyGhidra (`pyghidra.start()` + `pyghidra.open_program(..., analyze=False)`) para reabrir directamente el proyecto ya analizado y guardado (reusando los 105 minutos de análisis ya hechos) — funcionó a la primera.

**Hallazgo real:** `APalMonsterCharacter::SelectedFeedingItem` (la función real que arma el menú de selección de comida) NO tiene ningún chequeo de propiedad en su cuerpo — opera sobre cualquier puntero de personaje que reciba, y vive en la clase base de TODOS los Pals (salvajes u Otomo), no en algo exclusivo de Otomo. Esto confirma que el "muro" de propiedad real está en otro lado — el candidato más fuerte encontrado es un par de llamadas sin nombre al principio de la versión del menú (`UPalUIPlayerRadialMenuBase::SelectedFeed`) que resuelven algún objetivo interno ANTES de hacer nada, y abortan si sale nulo. Todavía no investigado más a fondo esta pasada — la aproximación actual (gesto + Happy, ya conectada al menú "4" real) sigue cubriendo Pet/Feed para Pals salvajes mientras tanto. Detalle técnico completo en `hook-points.md` ("Hundred-and-thirty-third pass").

Sin cambios de comportamiento del juego en esta pasada más allá de la limpieza de teclas (solo remoción de experimentos ya confirmados muertos). Verificado con `luaparse`, desplegado.

## Continuación 107 (2026-09-03): por qué el muro de "comida real" probablemente es un callejón sin salida genuino, no otro intento más de sustitución

Seguí investigando con Ghidra las dos llamadas sin nombre que bloquean el `SelectedFeed` real del menú del jugador. La primera (12 usos en todo el binario) tiene la forma de "conseguir mi propio jugador dueño, confirmar que es del tipo correcto". La segunda (32 usos) tiene la forma de "conseguir un componente, y llamar una función DIRECTO desde su tabla de funciones interna (vtable)" — es decir, una llamada nativa de C++ a C++, no una llamada que pase por el sistema de reflexión de Unreal (`UFunction`/`ProcessEvent`).

**Por qué esto importa más que cualquier otro hallazgo de esta investigación:** absolutamente todas las técnicas que este proyecto usa (`RegisterHook`, sobrescribir un valor de retorno, escribir un campo cacheado) solo funcionan porque interceptan llamadas que SÍ pasan por ese sistema de reflexión. Una llamada directa por tabla de funciones (vtable) no pasa por ahí para nada — UE4SS no tiene forma de interceptarla, sin importar qué tan bien esté hecho el intento.

**Conclusión probable (no 100% confirmada, pero bien fundamentada):** si esta llamada por vtable es la que de verdad resuelve "cuál es mi Otomo real" para el `SelectedFeed` del menú, entonces las dos sustituciones que ya probamos con cuidado (sobrescribir `TryGetSpawnedOtomo`, escribir el campo `SpawnedOtomo` del widget) nunca tenían chance de ser vistas por este camino — no porque estuvieran mal hechas (las dos se confirmaron escribiendo correctamente), sino porque esta resolución específica probablemente nunca lee ninguna de las dos cosas. Esto explica, por primera vez a nivel de mecanismo real y no solo "otro intento fallido", por qué nada de lo probado hasta ahora logró que `SelectedFeed` dispare para un Pal salvaje.

Confirmar esto al 100% necesitaría identificar la clase C++ real detrás de ese puntero y verificar que el offset de la vtable es realmente `TryGetSpawnedOtomo` — más trabajo de Ghidra del que se justifica ahora mismo, dado que la aproximación actual (gesto + Happy, ya conectada al menú "4" real) sigue cubriendo Pet/Feed para Pals salvajes. Queda documentado como la respuesta más completa que este proyecto ha tenido nunca sobre el "por qué" de este muro — y como una señal de que probablemente sea un callejón sin salida genuino desde Lua, no algo que solo necesite una sustitución más ingeniosa. Detalle técnico completo en `hook-points.md` ("Hundred-and-thirty-fourth pass").

## Continuación 108 (2026-09-03): encontrada y arreglada la causa REAL de por qué la personalidad nunca se pudo leer ni aplicar

Revisé el log de la prueba pedida (unos minutos cerca de Pals salvajes, más acariciar/alimentar un par, incluyendo uno que huía). Dos buenas noticias y un hallazgo real que cierra un misterio de varias sesiones.

**El arreglo del lag funcionó**: 41 líneas `[ENFORCE]` en toda la sesión, una por individuo, cero repetidas (antes eran 1170+).

**El diagnóstico de una sola vez por fin dio la respuesta, y coincide con un segundo dato independiente:** `GetComponentByClass` (la función que este mod usa para leer el sensor de IA de un Pal) devuelve un objeto fantasma/inválido absolutamente SIEMPRE para un Pal salvaje — confirmado con números reales: 41 de 41 intentos de enforcement, y 92 de 92 individuos nuevos leyeron "curious" (el valor de respaldo) en vez de su disposición real de especie, en una sesión completa de ~5 minutos. No es una carrera de tiempo al aparecer (5 minutos de reintentos ya lo habría resuelto si fuera eso) — es un camino roto para este componente específico, punto. Revisé también el volcado de cabeceras del juego: no existe ninguna función dedicada para leer este componente (a diferencia de `GetAIActionComponent()`, que sí existe para otro componente) — `GetComponentByClass` era la única palanca disponible, y simplemente no funciona aquí.

**Arreglado reusando una técnica que este mismo proyecto ya había probado con éxito** (la búsqueda del canvas real de la barra de vida en `Indicator.lua`, cuando `GetComponentByClass`/`RegisterHook` fallaron ahí también): `FindAllOf("PalAISensorComponent")` para encontrar todas las instancias reales ya vivas, emparejadas con su Pal dueño. Se reconstruye como máximo cada 5 segundos (nunca por cada Pal en cada chequeo, para no repetir el error de rendimiento de la pasada noventa y cuatro), compartido entre las dos partes del código que necesitan este dato.

Verificado con `luaparse`, desplegado en ambos destinos. **Prueba pendiente:** la misma de siempre (unos minutos cerca de Pals salvajes, acariciar/alimentar un par) — esta vez el log debería mostrar disposiciones reales de especie (no solo "curious"), líneas `[ENFORCE] SUCCESS` cuando corresponda, y que el intercambio real de comportamiento de "asustado → curioso" por fin funcione. Detalle técnico completo en `hook-points.md` ("Hundred-and-thirty-fifth pass").

## Continuación 109 (2026-09-03): encontrada la causa real del lag (un tercio del log entero venía de una investigación vieja nunca apagada) — y la personalidad sigue sin resolverse, honestamente

Dragón me cuestionó directamente por no creerle sobre el lag y propuso una prueba real (FPS con el mod activo vs. con todos los mods desactivados). Antes de proponer eso, desglosé el log fresco por volumen real en vez de solo revisar las etiquetas ya sospechosas.

**Encontrado algo real y nuevo, nada que ver con la personalidad:** `[INDICATOR-WATCH]` generó 1529 de 4630 líneas totales (un tercio) en una sesión de ~6 minutos. Son hooks de investigación vieja (de hace varias pasadas, para entender cómo apuntar "4" a un Pal específico) sobre el indicador genérico de "podés interactuar con esto" — que se dispara con CUALQUIER objeto interactuable del mundo (bayas, troncos, piedras, la Palbox, no solo Pals) cada vez que el jugador simplemente mira alrededor. La pregunta que estos hooks investigaban ya se había respondido hace varias pasadas — nadie volvió a apagarlos. Arreglado: comentados (no borrados, se conserva la investigación como documentación).

**Segundo contribuyente ya conocido, más chico pero real:** el escaneo de `find_targeted_pal` sigue costando 35-40ms cada vez que se abre el menú "4" cerca de un Pal salvaje — ya documentado desde la pasada setenta y siete, decidido no tocar en su momento. Sigue sin arreglar, mencionado de nuevo porque también contribuye al mismo síntoma.

**Honestidad sobre la personalidad — el arreglo anterior NO funcionó.** El respaldo con `FindAllOf` que implementé la pasada anterior también falló para los 98 Pals nuevos de esta sesión — cero presets reales leídos, igual que antes. Agregué un diagnóstico más para saber si `FindAllOf` no encuentra instancias en absoluto, o si las encuentra pero no logra emparejarlas con el Pal correcto — es un problema DISTINTO del lag, no la misma causa, solo se descubrieron juntos en la misma sesión de prueba.

Verificado con `luaparse`, desplegado en ambos destinos. **Sobre la prueba de Dragón**: la propuesta de comparar FPS con mods activos vs. desactivados sigue siendo válida y la haremos si el lag persiste después de este arreglo — mientras tanto, el propio tamaño del log de la próxima sesión (debería bajar notablemente sin las líneas de INDICATOR-WATCH) ya es una forma directa de confirmar si esto realmente ayudó, sin depender de una sensación. Detalle técnico completo en `hook-points.md` ("Hundred-and-thirty-sixth pass").

## Continuación 110 (2026-09-03): cambio de frente a pedido de Dragón — atacando la pregunta más grande del proyecto: ¿un Pal capturado de verdad ya sigue como un Otomo real?

Dragón, con razón, no quiso gastar una sesión entera solo en medir rendimiento — pidió elegir otro pendiente y seguir avanzando de verdad. Elegí **Follower Pal AI** (seguir/pelear como Otomo real) — la categoría con menor avance (45%) y la pregunta más repetida de todo este proyecto.

Leí a fondo el mod de referencia "PalFollowerTweaks" (antes solo revisado a medias). Confirma que `PalFunnelCharacter` (el mecanismo real detrás de Daedream/Dazzi/Flopie siguiendo como secundarios) es real, pero ese mod solo reposiciona/reescala seguidores que el JUEGO ya creó — nunca crea uno nuevo. Leyendo esto con cuidado: convertirse en `PalFunnelCharacter` casi seguro sigue necesitando ser miembro real de la party primero — el mismo paso que este proyecto YA resolvió (`PalCaptureSuccess`, captura real sin esfera, funcionando desde hace meses), no un atajo distinto.

**El verdadero hallazgo, razonando sobre lo que ya tenemos en vez de sobre el mod de referencia:** este proyecto tiene captura real sin esfera funcionando hace meses, pero NADIE confirmó nunca si un Pal capturado así de verdad sigue caminando con vos después, usando los sistemas reales del juego — o si simplemente se queda quieto en la banca del roster hasta que abrís el menú de party a mano y lo elegís. Toda confirmación anterior solo revisó "apareció en la pantalla de party", nunca "siguió siendo real después".

Agregué un diagnóstico de solo lectura (`diagnose_post_capture_slot`) que corre automáticamente después de cada captura real, reusando técnicas ya probadas y seguras (mismo patrón que `diagnose_party_membership` en Interaction.lua). Va a decir, en la próxima captura real, si el Pal quedó en un slot ACTIVO (significaría que ya sigue gratis, sin código nuevo) o solo en la banca (significaría que falta una sola llamada más, ya probada segura desde la Continuación 7).

Verificado con `luaparse`, desplegado en ambos destinos. **Prueba pendiente:** capturar cualquier Pal salvaje de verdad (llegando a confianza máxima, o con CTRL+K para una prueba rápida) y simplemente mirar si sigue caminando con vos después, sin tocar ningún menú. Esta sola prueba podría resolver de un tirón la pregunta más grande de todo el proyecto, o decirnos exactamente qué falta. Detalle técnico completo en `hook-points.md` ("Hundred-and-thirty-seventh pass").

## Continuación 111 (2026-09-04): arrancamos el punto 1 de la lista — interacción "Play" (mitad Pal-idle lista, falta un dato para la mitad del jugador)

Retomé el punto 1 de la lista de pendientes guardada. La idea de Dragón: al presionar Play, el jugador hace un emote real ("Cheer" — confirmó que es lo que él llama "Beckon" en el juego) y el Pal apuntado hace una animación de idle al azar, al mismo tiempo.

Investigué ambas mitades en el SDK antes de escribir nada (regla de siempre en este proyecto: nunca llamar algo sin probar antes). La mitad del Pal es sin riesgo nuevo: `PalRandomRest` (77) es un valor real del mismo enum simple que ya usamos para Happy/HumanPetting/HumanFeeding. La mitad del jugador es territorio nuevo pero con buena evidencia: los emotes reales NO pasan por ese enum simple — Dragón mandó un dump real de Live-View a mitad de sesión que lo confirmó directamente. Mostró 9 clases Blueprint reales (`BP_Action_Emote_0_C` a `_8_C`) y, más importante, una instancia VIVA: el juego había creado una de esas clases directo sobre el `ActionComponent` del jugador. Confirmé la función real en el SDK: `PlayAction(ActionTarget, actionClass)` — hermana de `PlayActionByType`, en el mismo componente que ya usamos en todo este archivo.

Lo que falta: cuál de las 9 clases es Cheer. En vez de adivinar un número y arriesgar una llamada en vivo a la clase equivocada, agregué un diagnóstico de solo lectura que corre una vez al iniciar (`log_emote_index_mapping`) — lee el campo `EmoteAnimation` de cada una de las 9 clases (una lectura de campo estática, cero riesgo, nada en vivo) y va a decirnos en el próximo log cuál índice es Cheer.

Lo que sí quedó andando esta pasada: `do_play()`, en CTRL+J (reciclada — la prueba de comida real quedó confirmada como callejón sin salida desde dos ángulos distintos, así que a Dragón le pareció bien reusar la tecla en vez de sumar una quinta). Hace la mitad del Pal de verdad: mismo apuntado/gating que Pet/Feed, reproduce `PalRandomRest` en el objetivo, y otorga confianza (Dragón confirmó que Play debía sumar lo mismo que Pet/Feed) con una sola llamada directa a `AddFriendShip` — sin el riesgo de doble-otorgamiento de la pasada once, porque acá solo hay una llamada, no dos.

Verificado con `luaparse`, desplegado en ambos destinos. **Prueba pendiente:** con solo abrir el juego una vez (ni hace falta jugar) el log va a mostrar el mapeo de las 9 clases — de ahí sacamos el único dato que falta para terminar la mitad del jugador. Aparte, CTRL+J ya debería mostrarse funcionando en el mundo: apuntar a un Pal salvaje, presionar, y ver la animación de idle + la confianza subir. Detalle técnico completo en `hook-points.md` ("Hundred-and-thirty-eighth pass").

**Mismo pase, dos refuerzos que pidió Dragón directamente.** Primero: como este proyecto ya tiene un arreglo probado para "una clase Blueprint que todavía no cargó al iniciar el mod" (el mismo patrón de reintento usado en el Radial Menu/Worker Menu/Indicator), lo apliqué YA en el diagnóstico estático en vez de esperar a ver si fallaba primero — ahora reintenta hasta 20 veces (100s) en vez de leerse una sola vez. Segundo, idea suya: además de la lectura estática, él mismo va a hacer el emote Cheer real en el juego mientras un hook en vivo escucha — confirmación por comportamiento real, un segundo método independiente que respalda al primero ("si el primero falla, el segundo lo respalda"). Reusé exactamente la misma maquinaria de reintento/hooks ya probada para el Worker Menu, solo agregando un intento de hook por cada una de las 9 clases numeradas.

**Crash real en el primer lanzamiento (Continuación 112, mismo día).** El primer intento de Dragón terminó en un crash real del juego (Fatal Error, crash dump), justo después de que el log mostrara la línea de "Play" — sin ninguna línea más después. Igual que en cada crash anterior de este proyecto, el único método que alguna vez encontró la causa real fue poner un log antes Y después de cada llamada nativa nueva, nunca adivinar. Agregué exactamente eso (`[CRASH-DIAG]`) alrededor de las tres cosas nuevas de esta pasada (el RegisterKeyBindAsync de Play, el escaneo estático EMOTE-DIAG, y el loop de 9 hooks en vivo EMOTE-WATCH) y envolví cada uno de los 9 intentos de hook en su propio pcall (antes corrían sin protección uno atrás del otro).

**Causa real encontrada (Continuación 113, mismo día) — segundo lanzamiento de Dragón, mismo crash, ahora con el dato exacto.** El log mostró la línea `[CRASH-DIAG]` justo antes de la falla: `anim:GetFName():ToString()`, una llamada a un método sobre el `UAnimMontage` leído del campo `EmoteAnimation` del CDO. Es una categoría de peligro NUEVA para este proyecto — cada `GetFName()`/`GetFullName()` anterior en todo este archivo siempre fue sobre un objeto vivo (actor/componente/widget), nunca sobre una referencia a un ASSET (una animación) leída directo de un class default object. La lectura del campo en sí es segura (el log mostró "still alive" ahí); es llamar un método sobre lo que devuelve lo que corrompe memoria. **Arreglado:** saqué esa llamada por completo — el diagnóstico ahora solo hace `tostring(anim)` (puramente del lado de Lua, no toca nada nativo) y sigue mostrando la identidad del asset igual. Nueva regla general para el proyecto: una lectura de campo exitosa NO garantiza que llamar un método sobre el resultado sea seguro — reservar `GetFName()`/`GetFullName()`/cualquier método para objetos confirmados como instancias vivas (actor/componente/widget), y usar `tostring()` para cualquier cosa leída de datos estáticos/assets hasta probar lo contrario. Detalle completo en `hook-points.md` ("Hundred-and-thirty-ninth" y "Hundred-and-fortieth pass").

## Continuación 114 (2026-09-04): Cheer confirmado por un dump real, primer intento en vivo, y diagnóstico del pool de descanso

Retest después del arreglo del crash: sin crash, la mitad del Pal funcionando (animación al azar confirmada). Reporte nuevo de Dragón: a veces esa animación se parece a la de Feed normal — preguntó si "PalRandomRest" rueda solo entre animaciones de idle o entre todas las del Pal. También mandó un dump real de un objeto (`BP_Action_Emote_0_C_2147458153.json`, sacado directo de la carpeta `IndividualObjectDumps` del juego) que resuelve la pregunta del índice sin adivinar más: `EmoteAnimation` = `AM_Player_Female_Emote_Cheer`, `EmoteIndex`="0" — **Cheer es `BP_Action_Emote_0_C`**. El mismo dump muestra que el cast real usa `ActionTarget=None` (no apunta a nada).

**Sobre el pool de descanso:** `APalCharacter` tiene un campo plano `StaticCharacterParameterComponent` con `RandomRestMontageInfos` — un array curado por especie (no "todas las animaciones"). Agregué un diagnóstico de solo lectura (`[REST-POOL-DIAG]`) que muestra el pool real de la especie apuntada cada vez que se presiona Play — así la próxima prueba muestra directamente si lo que pareció "Feed" es en realidad una animación de pastoreo/forrajeo legítima de esa especie (bastante probable para especies herbívoras) en vez de algo que se cuela de otro lado.

**Primer intento en vivo del lado del jugador:** cableé `playerActionComp:PlayAction(nil, cheerClass)` en `do_play()` — primera vez que este proyecto llama `PlayAction` (no `PlayActionByType`) y primera vez que pasa `nil` como AActor* (siguiendo el dato real del dump, no una suposición). Con el mismo logging `[CRASH-DIAG]` de antes por si este intento nuevo tiene su propio riesgo.

Verificado con `luaparse`, desplegado en ambos destinos. **Prueba pendiente:** presionar Play una vez más — ver si el jugador hace el gesto real de Cheer, revisar el log por `[CRASH-DIAG] PlayAction(Cheer) returned` (confirma que no crasheó) y por `[REST-POOL-DIAG]` para ver el pool real. Detalle en `hook-points.md` ("Hundred-and-forty-first pass").

## Continuación 115 (2026-09-04): dos bugs reales de la prueba anterior — Cheer nunca se disparó, y el diagnóstico del pool nunca imprimió ni una entrada

La prueba de Dragón no crasheó, pero encontró dos problemas reales. Confirmó directamente que la animación tipo Feed NO es una falsa alarma — conoce el set real de idles de ese Pal y no tiene nada parecido a Feed ahí, así que `PalRandomRest` de verdad está produciendo el gesto de Feed de alguna forma. Y el jugador nunca hizo el emote de Cheer.

**Causa real de lo de Cheer, encontrada directo en el log:** cada presión exitosa de Play cayó en el mensaje de "no se pudo resolver la clase de Cheer" — `PlayAction` nunca se llegó a llamar. El camino de `StaticFindObject` sobre la clase pelada (sin "Default__") falló siempre, mientras que el camino del CDO (CON "Default__", el mismo que ya usa `[EMOTE-DIAG]`) resolvió sin problema desde el inicio. Arreglado sacando la clase del CDO ya probado con `:GetClass()` en vez de confiar en un segundo formato de ruta sin verificar.

**Causa real de por qué el diagnóstico del pool nunca imprimió entradas:** había adivinado `restInfos:Get(idx)` para sacar elementos del array nativo — nombre de método equivocado, así que cada entrada volvía nil en silencio. Este proyecto ya tiene un patrón PROBADO para esto exacto, usado con éxito en el propio volcador de propiedades de `Indicator.lua`: `:ForEach(function(index, elem) ... end)`, desenvolviendo cada elemento con `:get()`. Reusado tal cual en vez de volver a adivinar.

**Todavía sin responder:** por qué `PalRandomRest` produjo algo parecido a Feed para un Pal que no tiene eso en su set real — los datos de `[REST-POOL-DIAG]` por entrada (ahora sí funcionando) deberían mostrarlo directo en la próxima prueba.

Verificado con `luaparse`, desplegado en ambos destinos. **Prueba pendiente:** presionar Play de nuevo. Esta vez se espera un gesto real de Cheer del jugador (o una línea de falla explicando por qué no) y las líneas completas de `[REST-POOL-DIAG] entry[...]` mostrando el pool real de montajes del Pal apuntado. Detalle en `hook-points.md` ("Hundred-and-forty-second pass").

## Continuación 116 (2026-09-04): corazones de Play investigados y cableados — encontrados con repak, no adivinados

Última pregunta abierta de Dragón sobre Play: algunas animaciones de idle no se ven particularmente felices — ¿se pueden mostrar los corazones/flores que aparecen en Pet/Feed también acá?

**Investigación con evidencia real (repak + strings, el mismo método ya probado en este proyecto).** Corrí `repak list` sobre el pak real (no había un listado guardado de antes), busqué nombres relacionados a corazón/afecto, y encontré `Pal/Content/Pal/Effect/Common/Emotions/`: `NS_Happy`, `NS_HappyPetting`, entre otros. Extraje `BP_ActionHappy.uasset` (el Blueprint detrás de la acción "Happy" que este mod ya usa) y confirmé que los corazones salen de adentro de su propio grafo (`SpawnSystemAtLocation`, carga dinámica de un Niagara System, posicionado sobre la cabeza) — no hay ninguna función separada en otro lado para disparar solo el efecto.

**Es un trade-off real, no un agregado simple:** `PalRandomRest` (la mitad del Pal) y `Happy` son mutuamente excluyentes en el mismo ActionComponent — no pueden pasar al mismo tiempo. Le presenté a Dragón las tres opciones reales (secuenciar idle-luego-Happy, cambiar a solo Happy perdiendo la variedad de idle, o dejarlo como está) — eligió secuenciar.

**Implementación:** después de la animación de idle, se agenda un Happy de seguimiento con un delay fijo de 3 segundos (aproximación honesta, no hay forma probada todavía de leer qué animación específica del pool eligió el juego ni su duración real). La confianza ahora viene SOLO del efecto secundario automático de Happy (mismo mecanismo que ya usan Pet/Feed) — saqué la llamada explícita a AddFriendShip que tenía antes, para no otorgar doble una vez que Happy también dispara la suya (el mismo bug de la pasada once, evitado de nuevo). Primera vez que este proyecto sostiene una referencia a un actor vivo a través de un timer de varios segundos — validado con `:IsValid()` antes de volver a tocarlo.

Verificado con `luaparse`, desplegado en ambos destinos. **Prueba pendiente:** presionar Play, esperar ~3 segundos después de la animación de idle, y ver si el objetivo hace Happy con los corazones. Revisar el log por la confirmación de que la confianza se otorgó una sola vez, no dos. Detalle en `hook-points.md` ("Hundred-and-forty-third pass").

## Continuación 117 (2026-09-04): la prueba real encontró el bug del busy-gate — Happy nunca se disparaba, algunas animaciones de idle duran 20+ segundos

Cheer siguió sin resolver (el arreglo de `:GetClass()` de la pasada anterior no ayudó), y Happy nunca se disparó. Dragón dio la razón real directamente: algunas de estas animaciones de descanso duran 20+ segundos reales — mucho más que el delay de 3s — así que el chequeo de "¿está ocupado?" del seguimiento de Happy siempre daba que sí, cayendo siempre en la rama de "saltando corazones". Su propio arreglo, tal cual: después del delay, cortar la animación de idle y forzar Happy sin importar si está ocupado.

**Arreglado:** saqué el chequeo de ocupado del seguimiento de Happy por completo — es el mismo `PlayActionByType` ya probado en todo este archivo, y acá tiene sentido forzarlo porque está cortando una animación que ESTE mod inició hace unos segundos, no algo orgánico del juego.

**Cheer sigue sin resolver — agregué diagnóstico en vez de adivinar un tercer arreglo a ciegas.** El CDO resuelve bien, pero algo en el paso de `:GetClass()` (o después) sigue fallando en silencio. Agregué logging `[CHEER-DIAG]` que reporta por separado si el CDO resolvió Y si `:GetClass()` en sí funcionó — así la próxima prueba señala exactamente cuál paso es el problema real.

Verificado con `luaparse`, desplegado en ambos destinos. **Prueba pendiente:** presionar Play de nuevo. Happy/corazones deberían dispararse siempre ~3s después de cada presión, sin importar cuánto dure la animación de idle. Revisar las líneas `[CHEER-DIAG]` para ver la razón real de por qué Cheer sigue sin resolver. Detalle en `hook-points.md` ("Hundred-and-forty-fourth pass").

## Continuación 118 (2026-09-04): Play dejó de funcionar por completo — `:GetClass()` de Cheer mataba la función en silencio, sacado del todo

Reporte de Dragón: Play dejó de hacer cualquier cosa — los Pals salvajes simplemente ignoraban la tecla. El log lo confirmó exacto: cada presión que llegaba a las entradas de `[REST-POOL-DIAG]` se cortaba justo después de la última — ni una línea `[CHEER-DIAG]` (lo primero que hace el código siguiente), ni animación de idle, ni Happy. `do_play()` estaba tirando un error sin capturar y muriendo en silencio, tragado por el `safe_call` de afuera — por eso no crasheaba nada pero Play tampoco hacía nada.

**Causa real, por eliminación:** lo único entre la última línea confirmada funcionando (el loop de REST-POOL-DIAG, sin cambios) y donde todo moría era el bloque de resolución de clase de Cheer de las últimas dos pasadas — específicamente `cheerCdo:GetClass()`, llamado sobre un CDO. Es muy probable una segunda instancia del mismo tipo de peligro que el crash real de la pasada cuarenta: un método que funciona bien sobre un actor vivo normal (`dump_interesting_properties` ya usa `:GetClass()` así, sin problema) no es automáticamente seguro sobre un CDO, aunque sea "el mismo" método. Esta vez no crasheó todo el juego — corrompió la llamada de Lua lo suficiente como para matar en silencio el resto de la función.

**Arreglado sacando todo el bloque de Cheer/PlayAction de `do_play()`** en vez de seguir iterando sobre un mecanismo cada vez más riesgoso que estaba rompiendo las dos cosas que sí funcionaban. La mitad del emote del jugador vuelve a quedar diferida para una investigación separada más adelante — igual que la decisión original antes de que el dump real de Dragón hiciera parecer esto más cerca de lo que en realidad estaba.

**Lección para el proyecto:** un método probado seguro sobre una CATEGORÍA de objeto (actores/componentes/widgets vivos) no es automáticamente seguro sobre una categoría DISTINTA (CDOs, referencias a assets) solo por ser "el mismo" método — van dos incidentes reales seguidos con exactamente esta suposición.

Verificado con `luaparse`, desplegado en ambos destinos. **Prueba pendiente:** presionar Play — debería volver a funcionar como dos pasadas atrás: animación de idle inmediata, Happy/corazones ~3s después sin importar cuánto dure el idle, sin emote del jugador (diferido de nuevo). Detalle en `hook-points.md` ("Hundred-and-forty-fifth pass").

## Continuación 119 (2026-09-04): Happy ahora sí corta la animación (CancelActionByType), y agregado FORCE_ALL_CURIOUS

Dragón: Play funciona y la animación de idle se reproduce, pero nunca hubo corte ni corazones. El log mostró que `PlayActionByType(pal, Happy)` devolvía "ok" desde Lua siempre, pero CERO líneas reales de `[WATCH] AddFriendShip fired` en toda la sesión — el motor lo ignoraba en silencio. El busy-gate de este proyecto no es solo cortesía, refleja una restricción real: una llamada nueva no interrumpe sola lo que ya está sonando.

**Arreglo, encontrado en el SDK:** `CancelActionByType(EPalActionType Type)`, al lado de `PlayActionByType`/`PlayAction`, mismo patrón simple ya probado. Ahora se cancela la animación de idle de verdad antes de reproducir Happy.

**Segundo pedido, mismo mensaje — forzar "curious" en todos los Pals salvajes.** Agregado `FORCE_ALL_CURIOUS = true` en `Personality.lua`, junto al toggle ya existente `ENABLE_PERSONALITY_TIER_ROLL` (mismo patrón de "apagar, no borrar"). El mecanismo de ENFORCEMENT ya existente no necesitó cambios.

**Aviso honesto, revisado directo en el mismo log antes de decir que esto funciona:** el swap real de ENFORCEMENT depende de `find_sensor_component`, el mismo bug sin resolver de las pasadas 135/136 (punto 4 de la lista guardada). El log de esta sesión por fin mostró datos reales de ese diagnóstico: `FindAllOf('PalAISensorComponent')` encontró solo 7 instancias (las 7 resolvieron bien), pero CADA búsqueda posterior por Pal siguió fallando — cero líneas `[ENFORCE] SUCCESS` en toda la sesión. Esto significa que **FORCE_ALL_CURIOUS va a guardar correctamente "curious" para cada Pal, pero el cambio de comportamiento real (que dejen de huir) sigue bloqueado por este bug previo, no arreglado en esta pasada.** Aviso esto directamente para que Dragón no piense que esto está roto cuando en realidad es el bug ya conocido.

Verificado con `luaparse`, desplegado en ambos destinos. **Prueba pendiente:** Play debería cortar y mostrar corazones siempre. Sobre personalidad: si los Pals salvajes siguen huyendo, confirma que el bug del sensor es el bloqueante real — punto 4 de la lista pendiente, ahora con mejor evidencia. Detalle en `hook-points.md` ("Hundred-and-forty-sixth pass").

## Continuación 120 (2026-09-04): el arreglo real para Pals calmados — copiar el mecanismo REAL del mod de referencia, no el resumen que ya teníamos

Dragón cuestionó directo la pasada anterior: "isnt the answer in the mod? the mod forces all pals to be pacific, you telling me you cant copy what the mod reference does?" Tenía razón — este proyecto llevaba tiempo intentando copiar el mecanismo POR INDIVIDUO del mod "Passive Pals" (búsqueda en vivo del sensor de cada Pal + copia privada del preset), que en realidad es su capa OPCIONAL, apagada por defecto. Releer el `main.lua` real completo (no solo el resumen que ya teníamos en los comentarios de este proyecto) mostró que su mecanismo PRINCIPAL es mucho más simple.

**El mecanismo real, copiado directo:** todo Pal salvaje que comparte un `AIResponsePreset` (Escape, Warlike, etc.) apunta al MISMO objeto compartido. El mod de referencia simplemente reescribe los 8 campos reales de ESE objeto compartido directamente — un solo write cambia a todos los Pals que lo usan, al instante, sin depender de encontrar el sensor de ningún Pal individual (el mecanismo bloqueado por el bug del punto 4).

**Implementación:** `apply_global_curious_preset_override()` en `Personality.lua` resuelve el CDO real de `BP_AIResponsePreset_friendly` (el mismo preset que ya usa nuestro tier "curious"), lee sus 8 valores reales, y los copia a los presets reales de huida/combate confirmados (`escape`, `Escape_to_Battle`, `Warlike`, `Warlike_Anyway`, `Warlike_WithoutPlayer`) — excluyendo los presets humanos confirmados por el mismo mod de referencia. Una sola protección copiada directo del mod: un campo que ya tiene el valor "Special" (3) se preserva, nunca se sobreescribe, porque la interacción de Pet/Feed de este proyecto probablemente depende de ese valor existiendo en algún lado real. Corre una sola vez por sesión, independiente del scan por individuo (que sigue corriendo pero ahora logueado honestamente como bloqueado por el bug del sensor, no "sin probar").

Deliberadamente más acotado que "todos los presets del juego": Default/NotInterested/Boss quedan sin tocar por ahora — pacificar jefes es una pregunta aparte que Dragón no pidió.

Verificado con `luaparse`, desplegado en ambos destinos. **Prueba pendiente:** los Pals salvajes deberían quedarse calmados de inmediato al acercarse (sin esperar ningún scan por individuo). Revisar el log por líneas `[GLOBAL-CURIOUS]` confirmando que cada preset se resolvió y reescribió, y confirmar en vivo que una especie que antes huía ahora se queda quieta. Detalle en `hook-points.md` ("Hundred-and-forty-seventh pass").

## Continuación 121 (2026-09-04): también el timing de Play a 6s, y el arreglo real del bug del sensor (punto 4) — un hook REACTIVO, no una búsqueda proactiva

Dragón confirmó que GLOBAL-CURIOUS funcionó de verdad en el juego, y preguntó algo clave: "if you can do this, why not put the randomizer there?" Le expliqué por qué el mecanismo global NO puede dar variedad por individuo (todos los Pals que comparten un preset comparten el mismo objeto), pero señalé la técnica real que sí puede: la capa "por especie" del mod de referencia, que nunca busca un sensor proactivamente. Dragón aprobó implementarla.

**El mecanismo real:** hookear `/Script/Pal.PalAISensorComponent:SelectResponseBySenses` — una función real que el juego llama cada vez que un Pal toma una decisión de IA. El propio hook entrega el sensor en vivo directo, sin necesitar `FindAllOf` ni matching por owner-key (el mecanismo confirmado roto). Desde el sensor, `sensor:GetOuter().Pawn` da el actor Pal real dueño — la dirección opuesta a como este proyecto lo venía intentando.

**Implementación:** refactoricé `try_enforce_personality` en un núcleo que no necesita encontrar el sensor por sí mismo, más dos llamadores — el scan proactivo de siempre (como respaldo) y un nuevo handler reactivo conectado al hook. Con la misma disciplina de siempre contra lag (deduplicar por sensor ANTES de cualquier trabajo pesado).

También arreglado el timing de Play: 3s cortaba animaciones a mitad de camino — subido a 6s a pedido de Dragón.

Verificado con `luaparse`, desplegado en ambos destinos. **Esto es muy probablemente el arreglo real del punto 4.** **Prueba pendiente:** buscar líneas reales `[ENFORCE] SUCCESS` (había cero en cada sesión anterior). Con `FORCE_ALL_CURIOUS` todavía activo, esto prueba el mecanismo pero no la variedad real — probar la variedad de verdad necesita apagar `FORCE_ALL_CURIOUS`, algo que Dragón no pidió todavía esta sesión, hay que preguntarle antes. Detalle en `hook-points.md` ("Hundred-and-forty-eighth pass").

## Continuación 122 (2026-09-04): FORCE_ALL_CURIOUS apagado para la prueba real de comportamiento

Dragón, con razón, no aceptó que las líneas `[ENFORCE] SUCCESS` en el log significaran que el sistema "funciona" — su propia regla: "if i cannot see it in game with their actions, then IT IS NOT WORKING - it has to be visible, not by code but by behavior." Correcto: con `FORCE_ALL_CURIOUS` activo, cada Pal siempre rolleaba "curious" — el mecanismo nunca tuvo que producir dos resultados DISTINTOS, solo el mismo repetido.

**Encontré una dependencia real antes de apagar el flag:** los presets que la pasada anterior reescribió globalmente (`Warlike`, `escape`) son EXACTAMENTE los mismos que el sistema por individuo usa como fuente para los tiers "hostile" y "skittish". Si solo apagaba `FORCE_ALL_CURIOUS` sin más, un Pal que rollara "hostile" igual se quedaría calmado, porque su fuente de datos ya estaba corrompida por el override global — la prueba hubiera parecido un fracaso sin probar nada real.

**No hizo falta código de reversión** — la corrupción del override global solo vive en la memoria del proceso del juego actualmente corriendo, nunca tocó el disco. Un reinicio real del juego recarga los presets frescos automáticamente.

`FORCE_ALL_CURIOUS` ahora en `false`. La tabla de pesos (50/25/10/15) sin tocar — comparar Pals de la misma especie con la distribución ya existente es la prueba real que pidió Dragón. Verificado con `luaparse`, desplegado en ambos destinos. **Prueba pendiente: reinicio REAL del juego (no solo continuar la sesión actual), apuntar a varios Pals de la misma especie y comparar su comportamiento real.** Detalle en `hook-points.md` ("Hundred-and-forty-ninth pass").

## Continuación 123 (2026-09-04): confirmado funcionando (147 individuos con roll real), más una etiqueta de texto temporal para comparar

¡Funcionó! Dragón confirmó comportamientos distintos en vivo. Números reales del log: 147 individuos con roll esta sesión — 21 hostile / 16 skittish / 43 curious / 67 normal, cerca del 10/15/25/50 esperado. No vio ningún hostile personalmente pese a los 21 — anotado para investigar después, no perseguido esta pasada.

**Nueva función, explícitamente temporal:** etiqueta de texto bajo la barra de confianza de cada Pal mostrando su disposición rolleada, para comparar contra el comportamiento real durante las pruebas — se puede sacar después. Implementado en `Indicator.lua` reusando la misma técnica ya probada para la barra de confianza (construir un widget nuevo, agregarlo al panel real, posicionarlo relativo a la barra) — la parte nueva es escribir texto en un TextBlock recién creado, primer intento de este tipo en el proyecto, puede necesitar una iteración.

Verificado con `luaparse`, desplegado en ambos destinos. **Prueba pendiente:** mirar la barra de confianza de un Pal salvaje — debería aparecer una etiqueta justo debajo con su palabra de disposición. Si no aparece nada, revisar el log por líneas `[DIAG-LABEL]`. Detalle en `hook-points.md` ("Hundred-and-fiftieth pass").

## Continuación 124 (2026-09-04): la etiqueta de personalidad crasheó en la primera prueba — arreglado con el mismo método de siempre

Crash real (EXCEPTION_ACCESS_VIOLATION, misma firma que otros crashes reales del proyecto). El log confirmó que es un crash nativo, no un error de Lua atrapado: se corta en silencio justo antes del bloque nuevo, sin ninguna línea `[DIAG-LABEL]` — el crash pasó adentro de una de las llamadas nuevas (StaticFindObject/StaticConstructObject/AddChildToCanvas/escritura de `.Text`) antes de que ni siquiera el primer log pudiera imprimirse.

En vez de adivinar, apliqué el único método que alguna vez encontró la causa real de un crash en este proyecto: logging antes y después de cada llamada nativa nueva. Sospechoso principal: la escritura de `.Text` (una propiedad, no un método) — un camino de datos nunca antes probado en este proyecto (posiblemente necesita un FText real, no un string plano de Lua).

Verificado con `luaparse`, desplegado en ambos destinos. **Prueba pendiente:** intentar de nuevo — podría volver a crashear, pero esta vez el log va a decir exactamente cuál llamada es la responsable. Detalle en `hook-points.md` ("Hundred-and-fifty-first pass").

## Continuación 125 (2026-09-04): causa real encontrada — una escritura directa de propiedad FText, arreglado con un método real ya confirmado

El logging `[CRASH-DIAG]` funcionó exactamente como debía: todo hasta `SetVisibility` imprimió "still alive", y el log se cortó justo después de "about to write labelObj.Text NOW" — la causa es `labelObj.Text = "?"`, escribir un string plano de Lua directo en una propiedad `FText`, algo que este proyecto nunca había intentado (todo lo demás siempre fue un escalar simple o un puntero).

**Arreglo:** en vez de una clase nativa genérica, la etiqueta ahora construye la clase de texto REAL del propio juego (`BP_PalTextBlock_C`, ya confirmada hace muchas pasadas), sacada directo de una instancia YA VIVA en el mismo gauge — y escribe el texto con `SetText_GDKInternal(bool, string)`, un método que este proyecto ya había confirmado hace meses que se ejecuta sin error (el único problema de aquella vez fue la visibilidad, ya forzada acá).

Verificado con `luaparse`, desplegado en ambos destinos. **Prueba pendiente:** intentar de nuevo — la prueba real y final de si esta función funciona. Detalle en `hook-points.md` ("Hundred-and-fifty-second pass").

## Continuación 126 (2026-09-04): renombre completo a nombres reales, 3 tiers nuevos, exclusión de NPCs/bosses

La etiqueta funcionó (sin crash) y confirmó la sospecha de Dragón: algunos "curious" en realidad huían. No fue solo un problema de etiquetas — encontré un bug real: `PRESET_NAME_TO_DISPOSITION` solo reconocía "Escape_to_Battle", nunca el "escape" plano, así que cualquier especie con ese default real caía al fallback y quedaba mal etiquetada "curious" (ahora "friendly"). Un roll "normal" en esas especies nunca se aplica (normal significa dejarlo como está), así que el Pal de verdad huye — la etiqueta solo mentía sobre por qué.

Dragón pidió usar los nombres reales para que este tipo de bug no vuelva a pasar, más 3 presets nuevos (NotInterested, Warlike_Anyway, Warlike_WithoutPlayer) para comparar los tres "warlike" en vivo, ya que el "Warlike" plano (hoy "hostile") no lo atacó en dos pruebas reales — coincide con la hipótesis de que es la variante condicional, no la incondicional.

**Renombrado en todo el archivo:** curious→friendly, hostile→warlike, skittish→escape, normal sin cambios. Arreglado el bug de "escape", agregados los 3 tiers nuevos.

**Nueva distribución** (números de Dragón, suma 100): normal 35 / friendly 20 / escape 10 / notinterested 10 / warlike 5 / warlike_anyway 10 / warlike_without_player 10. El total de "ataca de alguna forma" subió de 10% a 25% — avisado a Dragón como un cambio de balance real, no absorbido en silencio.

**Nueva exclusión**, pedido de Dragón ("npc, bosses and other things, those should stay normal always"): antes, el roll corría sin condición sobre cualquier actor visto, incluyendo NPCs humanos y jefes. Agregada `EXCLUDED_FROM_ROLLING` — cualquier Pal cuyo preset real actual sea VillageNPC/Kill_All/Boss queda forzado a "normal" siempre, sin pasar por el roll.

Verificado con `luaparse`, desplegado en ambos destinos. **Prueba pendiente:** la etiqueta ahora debería mostrar los nombres reales, para comparar warlike/warlike_anyway/warlike_without_player contra la agresión real observada, y confirmar el arreglo del bug de "escape". También confirmar que ningún NPC/jefe muestre otra cosa que no sea su propio default real. Detalle en `hook-points.md` ("Hundred-and-fifty-third pass").

## Continuación 127 (2026-09-04): confirmado funcionando, pero lag por logging de crash que quedó sin sacar — arreglado

¡Los Warlike de verdad atacaron esta vez! También reportó lag real y preguntó por Pals con "?" en la etiqueta.

**Lo de "?", respondido directo del log:** es solo el placeholder inicial — confirmé varios Pals reales (SheepBall, PinkCat, ChickenPal, PlantSlime) escribiendo "?" al crear la etiqueta y después la palabra real unos segundos después. No es un bug nuevo del sistema de roll — si algún Pal específico se quedó en "?" toda la sesión, seria una limitación aparte y ya conocida (ese gauge nunca resuelve su actor real), no algo del sistema de personalidad.

**El lag real, encontrado desglosando el log por volumen, no adivinando:** `[CRASH-DIAG]` (el logging de investigación de la pasada anterior) era 516 de 981 líneas de Indicator en 140 segundos — más de la mitad, cada una una escritura forzada a disco. El crash que buscaba ya se había encontrado y arreglado — el logging simplemente nunca se sacó. Mismo patrón de lag autoinflingido que ya se arregló una vez antes en este proyecto (`[INDICATOR-WATCH]`). Recortado a una sola línea de resultado por evento.

Verificado con `luaparse`, desplegado en ambos destinos. **Prueba pendiente:** mismo test — el volumen del log debería bajar a la mitad y el lag debería notarse menos o desaparecer. Detalle en `hook-points.md` ("Hundred-and-fifty-fourth pass").

## Continuación 128 (2026-09-04): el "?" que se quedó toda la sesión — una carrera real en el bind-hook, investigada y arreglada en la fuente

Dragón pidió investigar de verdad en vez de dejarlo como un detalle sin resolver. Confirmé por el log que cero líneas de "actor resuelto" mencionan el samurai dog en toda la sesión — prueba directa de que es el problema de binding del gauge, no el sistema de personalidad.

**Causa real:** el hook de `BindFromHandle` (a nivel de CLASE, una vez registrado captura TODAS las instancias futuras) solo se registra la primera vez que el scan periódico de este archivo descubre un gauge — no de inmediato al iniciar. Cualquier gauge que ya estaba en pantalla y ya vinculado antes de ese momento exacto queda perdido para siempre (BindFromHandle solo dispara una vez por vínculo).

**Arreglo en dos capas:** (1) el primer candidato de ruta ya es un string literal comprobado, sin necesitar un gauge en vivo — lo saqué a una función nueva que se registra de inmediato al iniciar Indicator, en vez de esperar el descubrimiento del scan. (2) `Indicator.Init()` corría sexto de ocho módulos en `main.lua` — lo moví a segundo, justo después de Logger. Verifiqué que esto no rompe nada: Indicator ya tiene el módulo de Personality cacheado sin importar el orden de Init(), y solo lo USA en su propio loop, mucho después de que todos los Init() terminen.

**Aviso honesto:** esto cierra casi toda la ventana de carrera, no necesariamente el 100% — sigue existiendo un hueco mínimo entre que arranca el proceso del juego y que corre este mod, fuera de nuestro control.

Verificado con `luaparse`, desplegado en ambos destinos (`Indicator.lua` y `main.lua`). **Prueba pendiente:** mismo test, idealmente cerca de un Pal que ya esté visible justo al terminar de cargar el juego. Detalle en `hook-points.md` ("Hundred-and-fifty-fifth pass").

## Continuación 129 (2026-09-04): huida real al perder confianza — punto 2, reusando el mismo mecanismo ya probado hoy

Dragón, con razón, no quería que la próxima prueba fuera de solo 2 segundos — pidió sumar algo más. Revisé la lista guardada en vez de inventar: el punto 2 (huida real al perder toda la confianza) seguía abierto — `Capture.OnTrustLost` solo marcaba una bandera interna, con un TODO honesto admitiendo que nunca se intentó la huida real porque parecía una llamada nueva y riesgosa.

**Ya no lo es.** Esta misma sesión ya probó en vivo un mecanismo real para hacer que un Pal huya de verdad: forzar su tier a "escape" y dejar que el enforcement (ya confirmado funcionando) lo aplique. Sin llamada nativa nueva.

**Implementación:** `Personality.ForceTier(palId, palActor, tier)` — versión genérica del mecanismo WON-OVER ya existente, pero para la dirección opuesta. `Capture.OnTrustLost` ahora la llama con tier="escape".

**Aviso honesto:** el hook reactivo deduplica por identidad de sensor, no por tier — un Pal cuyo sensor ya disparó una vez no será recapturado por ese hook para un tier nuevo después. Solo el intento inmediato y el scan proactivo (menos confiable) pueden reintentarlo. Si la huida no se ve de inmediato, revisar esto primero.

Verificado con `luaparse`, desplegado en ambos destinos. **Prueba pendiente, junto con la del bind-hook:** dejar que la confianza de un Pal llegue a cero y ver si huye de verdad. Revisar el log por líneas `[FORCE-TIER]`. Detalle en `hook-points.md` ("Hundred-and-fifty-sixth pass").

## Continuación 130 (2026-09-04): el arreglo del bind-hook falló en su propia primera prueba — sin reintento — más datos reales de las 2 discrepancias restantes

Dragón: el "?" seguía apareciendo, algunos Pals seguían sin coincidir con su rol, varios fallos visibles en la consola, y no pudo probar la huida real por las discrepancias de personalidad. Investigué las tres cosas directo del log.

**El "?" — un bug real en el arreglo de la pasada anterior:** `register_bind_hook_immediate()` falló de entrada al iniciar — la clase de Blueprint todavía no estaba cargada en memoria a esa hora. Sin reintento, cayó en silencio al mismo mecanismo de siempre (el scan) — el arreglo de la pasada anterior no logró nada en esa prueba. **Arreglado** convirtiéndolo al mismo patrón de reintento acotado ya probado en todo el proyecto.

**Fallos de consola — casi todos normales, uno real ya cubierto arriba.** La mayoría son el mismo ruido esperado de siempre (ronda 1 falla, rondas después funcionan) — no es nuevo. El único real y nuevo es el del bind-hook, ya arreglado.

**Discrepancias de personalidad — reales, medidas, no una percepción.** 40 individuos con roll no-normal esta sesión, 37 con `[ENFORCE] SUCCESS` real, y exactamente 2 casos reales sin aplicar (de un tercero que coincidía con su default de todos modos). ~95% de éxito real — un hueco chico y probablemente probabilístico, no perseguido más esta pasada.

Verificado con `luaparse`, desplegado. **Prueba pendiente:** mismo test — el bind-hook ahora sí tiene reintento real. Las discrepancias de personalidad deberían ser raras (un par, no "varias") si el diagnóstico de hoy es correcto. Detalle en `hook-points.md` ("Hundred-and-fifty-seventh pass").

## Continuación 138 (2026-09-05): prueba base confirmada (9/9 sin enganche nativo), copia de ownership descartada por riesgo, y con Ghidra se encontró un camino nuevo real para Feed con ítem real

La prueba base de la Continuación 137 dio un resultado limpio: en 9 presiones reales de "4" sobre Pals confirmados salvajes, el enganche nativo (`StartTriggerInteract ActionType=4`) nunca disparó — ni una vez. En la décima, apuntando a un Pal que YA era trabajador real, disparó al instante. Esto separa bien la hipótesis (1) apuntado impreciso y (3) gate estructural ligado a propiedad real, de la hipótesis (2) radio de base — pero (2) y (3) siguen mezcladas en estos datos (el único éxito fue dueño Y cerca de una base).

Para separar (2) de (3) haría falta apuntar a un Pal propio lejos de cualquier base — pero eso implicaría copiar/falsificar datos reales de propiedad (`OwnerPlayerUId`) sobre un Pal salvaje. Dragón lo descartó de inmediato, con razón: "that one has the risk of overriding a base pal isnt it? or corrupting its data since we would be copying it." Mismo tipo de riesgo que el incidente de la pasada 82 (un valor real copiado colisionando con la identidad de otro Pal). Esa disambiguación queda archivada, no perseguida.

**Dragón cuestionó aceptar la aproximación actual (gesto + Happy) como suficiente** ("if the game has a system of feeding through an inventory and picking the item, is it enough for you that we simply don't use it? — I feel like it's a sloppy job... what else are we not seeing?"). Volví a Ghidra (mismo proyecto ya analizado de las pasadas 133-134) a revisar `SelectedFeedingItem` a fondo — la única función ya confirmada sin ningún chequeo de propiedad en su propio cuerpo.

**Primera lectura del decompilado fue prometedora pero NO confiable por sí sola**: Ghidra reportó "calling convention: unknown"/"parameter count: 0" para esta función — su propia recuperación automática admitió haber fallado, así que una lectura de "solo un parámetro" no se podía confiar a ciegas (contradice la firma real ya confirmada por el header dump y por nuestro propio hook funcionando: `SelectedFeedingItem(FPalItemSlotId, int64)`). En vez de actuar sobre eso, un segundo script revisó el DISASSEMBLY CRUDO del punto de llamada real (dentro de `OnSelectedOrderWorkerRadialMenu`, la función que este proyecto YA usa como blanco de un delegate — Continuación 64) justo antes de llamar a `SelectedFeedingItem`. Confirmación a nivel de registro, no de pseudocódigo: solo `MOV RCX,RDI` (el "this") se carga antes del `CALL` — RDX/R8/R9 sin tocar. **Esa llamada específica de verdad solo pasa UN argumento (el Pal mismo).**

**El mecanismo real, cruzando esto con el resto del decompilado de `OnSelectedOrderWorkerRadialMenu`:** lee un byte `resultType` de su parámetro (el enum `EPalWorkerRadialMenuResult`, confirmado independientemente contra el mapeo real ya conocido desde la pasada 56: Cancel=0/Feed=1/ShowDetail=2/MoveToBox=3/MoveToOtomo=4/Pet=5 — las ramas `cVar3=='\x01'` y `'\x05'` llaman exactamente a SelectedFeedingItem y a una función de Pet separada) y despacha según eso — **sin ningún chequeo de propiedad en su propia lógica tampoco**, solo una verificación de tipo sobre el parámetro. El mecanismo real de dos pasos: elegir Feed en el menú de Worker llama `OnSelectedOrderWorkerRadialMenu(resultType=Feed)` → eso llama `SelectedFeedingItem(self)` con SOLO el Pal, que solo construye y muestra un popup real de elegir ítem (sin ítem elegido todavía) → recién cuando el jugador elige algo, el delegate propio del popup dispara la función YA confiable y observada en vivo `SelectedFeedingItem(ItemSlotId, Num)` (2 argumentos). El Crash #5 intentó saltar directo a ese segundo paso, en frío, con un ItemSlotId inventado y sin que el popup hubiera existido nunca — explica el crash sin necesidad de declarar todo el mecanismo inalcanzable.

**Experimento nuevo implementado** (`Interaction.lua`, CTRL+H reutilizado por tercera vez — el código de BaseCampId queda intacto, solo desconectado de la tecla): `do_test_direct_feed_dispatch()` busca una instancia viva de `PalHUDDispatchParameter_WorkerRadialMenu` ya en memoria (reutilizada, no construida — necesita que se haya abierto el menú de Worker real al menos una vez esta sesión), le escribe `resultType=1` (Feed) y `IndividualHandle` apuntando al Pal (salvaje incluido), y llama `pal:OnSelectedOrderWorkerRadialMenu(parameter)` directo — pasando por el despacho reflejado real de Unreal (el motor mismo arma la convención de llamada, no nosotros), nunca una llamada nativa reconstruida a mano. Si funciona, debería abrir el popup real de elegir ítem sobre un Pal salvaje, sin el riesgo específico que causó el Crash #5.

**Riesgo residual honesto**: primera vez que este proyecto llama `OnSelectedOrderWorkerRadialMenu` nosotros mismos, no solo lo usamos como blanco de un delegate; la resolución interna de `SelectedFeedingItem` de a qué servicio de HUD/UI se cuelga su popup no está trazada de punta a punta. Con permiso explícito de Dragón ("don't be afraid of the crashes as long as we can recover from them... the reward is high"), se avanza igual, con logging pesado (`[DIRECT-FEED-TEST]`), un Pal a la vez.

Verificado con `luaparse`, desplegado al juego real. **Plan de prueba:** presioná "4" sobre un trabajador de base real una vez esta sesión primero (para que exista una instancia real del parámetro en memoria), después apuntá CTRL+H a un Pal salvaje y presioná una vez. Fijate si aparece un popup real de elegir ítem en pantalla — avisame de inmediato si algo se ve mal. Detalle técnico completo en `hook-points.md` ("Hundred-and-sixty-fifth pass").

## Continuación 139 (2026-09-05): la prueba se quedó en silencio — un bug de logging propio, no un resultado real

Dragón probó de nuevo (un menú de Worker real se abrió dos veces sobre un trabajador de base real, con una selección de Feed real confirmada en el log — o sea, sí existía una instancia real en memoria) y reportó "didn't see any different." El log mostró la línea `[DIRECT-FEED-TEST] targeting...` y después NADA más — ni siquiera la rama de "no se encontró instancia", que debería haber logueado sí o sí si la función simplemente devolvía nil.

**Causa real: `safe_call()` (ya existente en este proyecto) traga errores sin loguear nada, a propósito** — correcto para código ya probado, mal para una técnica genuinamente nueva. `FindAllOf("PalHUDDispatchParameter_WorkerRadialMenu")` era la primera vez que este proyecto busca esta clase directo (siempre se había tocado vía el `Context` de un hook) — y no estaba envuelta en su propio pcall, así que cualquier error ahí se propagó hacia arriba y quedó tragado en silencio por el `safe_call` del bind de tecla. Mismo patrón de "silencio autoinfligido" que ya pasó antes con código genuinamente nuevo.

**Arreglado:** el `FindAllOf` y el loop de búsqueda ahora tienen su propio pcall con logging explícito (reporta el error crudo si `FindAllOf` mismo falla, o cuántas instancias encontró/válidas), y el bind de tecla ahora usa un `pcall` que sí loguea en vez del `safe_call` silencioso — así cualquier error que quede en el resto de la función va a aparecer la próxima vez, no silencio.

**Esto significa que la idea real (llamar `OnSelectedOrderWorkerRadialMenu` directo) todavía no se probó de verdad** — la prueba nunca pasó del paso de búsqueda, por una razón que no tiene nada que ver con si el plan basado en Ghidra es correcto. Verificado con `luaparse`, desplegado. **Plan de prueba, igual que antes:** presioná "4" sobre un trabajador de base real una vez esta sesión, después apuntá CTRL+H a un Pal salvaje y presioná una vez — esta vez el log debería mostrar detalle real pase lo que pase. Detalle en `hook-points.md` ("Hundred-and-sixty-sixth pass").

## Continuación 140 (2026-09-05): el arreglo de logging funcionó al instante — un bug simple de orden, ya arreglado, todavía sin probar el experimento real

El arreglo de logging funcionó exactamente como se esperaba: en vez de silencio, el log mostró un error de Lua claro y accionable — `attempt to call a nil value (global 'hook_describe')`, justo en la línea que lo llamaba. Progreso real también: `FindAllOf` encontró la instancia viva correctamente ("FindAllOf found 1 instance(s) total").

**Causa real: un bug simple de orden, nada que ver con el diseño del experimento.** `hook_describe` es una función local declarada MÁS ADELANTE en este mismo archivo — los locales de Lua no se "hoistean", así que código declarado antes que la referencia simplemente resuelve como global (nil, ya que nunca se declara global). `do_test_direct_feed_dispatch` está ubicada antes del punto donde se declara `hook_describe`.

**Arreglado** sin depender de ella: se puso en línea el mismo patrón seguro (`pcall` leyendo `:GetFullName()`, con respaldo a `tostring`) directamente, evitando la dependencia de orden en vez de mover código y arriesgar tocar otra cosa.

**Sigue siendo cierto que el experimento real (llamar `OnSelectedOrderWorkerRadialMenu` sobre un Pal salvaje) todavía no se alcanzó en ninguna de las dos pruebas.** Verificado con `luaparse`, desplegado. Plan de prueba sin cambios: presioná "4" sobre un trabajador de base real una vez esta sesión, después CTRL+H sobre un Pal salvaje. Detalle en `hook-points.md` ("Hundred-and-sixty-seventh pass").

## Continuación 141 (2026-09-05): CONFIRMADO — Feed real con inventario funciona en un Pal salvaje, primera vez en la historia del proyecto

Dragón probó y confirmó éxito real, dos veces: apuntando CTRL+H a un Sheepball salvaje, apareció un popup real de elegir ítem, eligió Berries, y el Pal comió. El log lo confirma sin ambigüedad: `real SelectedFeedingItem fired` con `pal=BP_SheepBall_C` seguido de `real PalItemSlot:RequestUseToCharacter fired` con `ItemId.StaticId=Berries` — la misma cadena real de consumo nativo ya confirmada para el Otomo propio, ahora disparando para un Pal genuinamente salvaje. Pasó dos veces en la misma sesión, limpio.

**La "confusión del Pal equivocado" NO fue un bug de ruteo — los dos CTRL+H apuntaron al MISMO actor.** Cruzando los logs: ambos intentos exitosos apuntaron al mismo Sheepball (`_2147453268`) — el propio apuntado de Dragón cayó dos veces sobre el mismo, no sobre dos distintos como pensaba. El Sheepball alimentado con la animación "sin inventario" fue un actor genuinamente distinto (`_2147453281`), nunca tocado por CTRL+H, alimentado por el camino de aproximación de siempre — dos Sheepballs parecidos parados cerca, no un cruce de identidad.

**Corrección mía: dejé de usar F10 hace tiempo, seguís usando "4" como corresponde** — mencioné F10 por error en mi respuesta anterior, confundiendo el flujo viejo con el actual.

**CORREGIDO — Dragón me corrigió directo, y tenía razón.** Mi primera lectura (basada solo en que `InputSpy` no mostraba ningún "FOUR" en la ventana de 3 segundos) concluyó que CTRL+H solo ya bastaba. Dragón corrigió de inmediato: "wrong, there was 4 press and the otomo radial menu did open... trust in my word above all - we already confirmed your readings through the log are flawed and can sometimes fail." Tiene razón — `InputSpy` (un listener de ~150 teclas registradas por separado) aparentemente se perdió una presión real esta vez, un límite real y recién descubierto de esa herramienta puntual, no evidencia de lo que pasó de verdad en el juego. La receta real y confirmada es: **CTRL+H, después "4" → elegir Feed en la rueda del Otomo (ya sustituida)** — los dos pasos son reales y necesarios, en ese orden, las dos veces.

**Teoría propia de Dragón, más precisa que la mía:** "i think the ctrl + h made the wild pal eligible as an owned pal, which was the needed confirmation from the otomo radial menu to work." Esto encaja perfecto con el muro exacto que este proyecto viene golpeando desde la Continuación 97/pasada 134: el `SelectedFeed` real del widget de Otomo arranca con una llamada de vtable cruda e inalcanzable desde Lua, cuyo trabajo más probable es resolver "¿es este actor un objetivo válido para mí?" — todos los intentos anteriores (sobrescribir `TryGetSpawnedOtomo`, escribir el campo cacheado `SpawnedOtomo` del widget) fallaron porque ninguno de los dos es lo que esa llamada realmente lee. Si la llamada de CTRL+H (`OnSelectedOrderWorkerRadialMenu`/`SelectedFeedingItem`) registra al Pal salvaje en algún lugar que ESA MISMA resolución de vtable sí lee, entonces CTRL+H no necesita abrir ningún popup visible por sí solo — su trabajo real sería hacer que el Pal salvaje satisfaga ese gate específico, para que el "4"→Feed inmediato siguiente complete por fin el camino que nunca había funcionado antes. Sería la respuesta real a un misterio de meses — no confirmado con certeza todavía, pero es la lectura del propio Dragón, no una que salió solo de mirar el log.

**Pregunta real de Dragón, la más importante: ¿esto depende para siempre de haber alimentado antes a un trabajador de base real?** No — eso fue una elección cautelosa de esta pasada, no un requisito real del mecanismo. `find_any_worker_menu_parameter()` solo reutilizaba un objeto ya existente en memoria (que solo existía porque se había alimentado antes a un Chikipi real) porque reusar un valor real es la costumbre de menor riesgo de este proyecto — no porque la rama de Feed de `OnSelectedOrderWorkerRadialMenu` necesite estructuralmente que venga de una interacción real. Según el rastreo de Ghidra, esa rama solo lee `resultType` del parámetro. **Arreglado esta pasada:** agregado `construct_worker_menu_parameter()`, con la misma técnica `StaticFindObject`+`StaticConstructObject` ya probada segura en este proyecto (la barra de confianza y la etiqueta de personalidad en Indicator.lua) — esta vez para un objeto de parámetro plano, un paso más chico que construir un widget. `do_test_direct_feed_dispatch` ahora intenta reusar primero (gratis, sin riesgo, cuando existe) y recién si no hay nada construye uno fresco — así debería funcionar de cero en una partida nueva, sin haber tocado nunca a un trabajador real. Sin confirmar en vivo todavía.

**Crédito de confianza/amistad deliberadamente NO conectado todavía, por instrucción explícita de Dragón** ("don't focus on the friendship gain for now, lets focus on polishing this and seeing where it could fail") — confirmado por el log que no disparó ningún `AddFriendShip` en toda la sesión, así que este camino real todavía no otorga ningún progreso de confianza. Queda como hueco conocido y deliberado para una pasada futura.

**Receta real confirmada (según el relato directo de Dragón, no la lectura fallida del log de arriba): CTRL+H, después "4" → elegir Feed en la rueda del Otomo sustituida — los dos pasos son reales y necesarios, en ese orden.** CTRL+H solo no muestra nada en pantalla; es el "4" siguiente el que completa el feed real.

Verificado con `luaparse`, desplegado. **Próxima prueba real:** confirmar que el nuevo respaldo de construcción (`construct_worker_menu_parameter`) funciona en un Pal donde nunca se abrió un menú de Worker real esta sesión (por ejemplo, apenas cargando la partida, antes de alimentar a cualquier trabajador real) — usando la misma receta CTRL+H→"4"→Feed. Detalle completo en `hook-points.md` ("Hundred-and-sixty-eighth pass").

## Continuación 142 (2026-09-05): probando de verdad la teoría de Dragón, y un spy dedicado para "4" pedido explícitamente

Dos agregados, ambos de solo diagnóstico, pedidos directo por Dragón.

**Probando la teoría de propiedad de verdad, no solo discutiéndola.** `Capture.IsAlreadyOwned` lee el GUID real `SaveParameter.OwnerPlayerUId` — el mecanismo exacto que su teoría propone que CTRL+H podría cambiar. Agregado logging `[OWNERSHIP-CHECK]` (los componentes crudos del GUID, no solo el booleano) en tres momentos: justo antes de la llamada a `OnSelectedOrderWorkerRadialMenu`, justo después de que retorna, y — el punto más informativo — justo cuando dispara el consumo real de `SelectedFeedingItem` (dentro del hook `[FOOD-DIAG]` ya existente). Si su teoría es exactamente correcta, `OwnerPlayerUId` debería mostrar un GUID real y no-cero en algún punto donde antes era todo ceros; si se queda en todo-ceros durante todo el proceso aunque el feed real funcione, apunta más a un mecanismo más angosto y específico de Feed en vez de un cambio real de propiedad. Puramente de lectura, cero riesgo.

**Spy dedicado y separado para la tecla "4", por instrucción directa de Dragón** ("put a spy everytime i press 4... just when i press '4' in the keyboard"), separado del listener masivo de ~150 teclas de `InputSpy.lua` que justo se perdió una presión real de "4" esta misma sesión. Un solo `RegisterKeyBind(Key.FOUR, ...)` aparte, logueando solo `[FOUR-KEY-SPY] "4" pressed` — nada de menús, nada de éxito/fracaso, tal cual se pidió. Separado a propósito por si registrar ~150 teclas de una sola vez es justo lo que hace que `InputSpy` a veces se pierda una.

Verificado con `luaparse`, desplegado. **Plan de prueba:** repetir la receta CTRL+H→"4"→Feed sobre un Pal salvaje y revisar el log por `[OWNERSHIP-CHECK]` en los tres puntos, además de confirmar que `[FOUR-KEY-SPY]` esta vez capture cada "4" real de forma confiable. Detalle completo en `hook-points.md` ("Hundred-and-sixty-ninth pass").

## Continuación 143 (2026-09-05): cuelgue real encontrado y reproducido — reasignar un parámetro reusado a un Pal DISTINTO traba la tecla CTRL+H; la teoría de propiedad probada directo, salió negativa en ese campo específico

Dragón hizo una sesión de prueba real con varios Pals, pidiendo que lea el log a ciegas antes de escuchar su relato, y después cuestionó bien y directo la teoría de "reusar rompe todo" de la pasada anterior: la sesión exitosa de antes TAMBIÉN reusaba un objeto real dos veces, ¿por qué ahora sería inseguro?

**Teoría de propiedad, probada directo, salió negativa en ese mecanismo específico.** `[OWNERSHIP-CHECK]` mostró `IsAlreadyOwned=false`/GUID todo-cero en los tres puntos (antes de la llamada, después, y en el consumo real) para el intento exitoso de esta sesión. El GUID real de propiedad nunca cambió. No descarta que algo ADYACENTE a propiedad sea cierto por otro campo, pero el mecanismo literal que propuso Dragón no apareció acá.

**El bug real, encontrado del log solo, antes de que su relato lo confirmara:** dos intentos de CTRL+H esta sesión. El primero (parámetro recién construido, Sheepball salvaje) completó limpio — logueó "call returned — result=ok" al instante, feed real después. El segundo (reusando ESE MISMO objeto ya usado, pero reasignado a un Pal DISTINTO — un Chickenpal salvaje) nunca logueó "call returned" — la única llamada así en toda la historia de este proyecto que no completó. Peor: **no hay ninguna línea "CTRL+H pressed" en el resto de la sesión después de ese punto** — pese a que Dragón confirmó haberla presionado al menos dos veces más (en un Daedream, después un Gumoss). La llamada no solo no terminó — trabó la tecla CTRL+H misma por el resto de la sesión, en la misma forma silenciosa y sin crash que el Crash #5, solo con menos alcance (aquel trababa toda la capa de input; este traba el callback async de una sola tecla).

**Resolviendo el cuestionamiento exacto de Dragón — ¿por qué funcionó el reuso antes, entonces?** Revisé de nuevo los IDs de actor de esa sesión anterior: sus dos presiones de CTRL+H cayeron sobre el MISMO Sheepball las dos veces (ya establecido en la Continuación 141) — el objeto se reusó para el MISMO Pal al que ya estaba asignado, nunca se reasignó a uno distinto. El segundo intento de esta sesión fue la primera vez que un objeto ya usado se reasignó a un Pal genuinamente distinto, y esa acción específica es la que parece disparar el cuelgue. No es "reusar es inseguro" en general — es "cambiar a qué Pal apunta un parámetro de despacho ya usado."

**Esto también explica cada detalle restante del relato de Dragón, limpio:** el Lamball se alimentó dos veces (una por la aproximación `[WILD-ACTION]` de siempre que "4"+Feed siempre dispara sin relación con CTRL+H, otra por el inventario real del CTRL+H exitoso — dos sistemas independientes, no un bug); el popup del Chikipi se abrió pero no mostró nada y hubo que cerrarlo con Escape (una UI a medio construir, resto del cuelgue); y los intentos del Daedream/Gumoss cayeron en la animación simple sin popup real porque CTRL+H ya había dejado de responder para entonces.

**Arreglado:** `do_test_direct_feed_dispatch` ya no llama a `find_any_worker_menu_parameter()` (reuso) para nada — ahora construye un objeto nuevo en cada intento, sin condición. La función de reuso queda en el archivo, sin usarse, con una nota explicando por qué. También cambié el spy de "4" de `RegisterKeyBind` a `RegisterKeyBindAsync` — el mismo mecanismo que usan CTRL+H/CTRL+K/Play, que nunca se perdieron una presión en toda la historia del proyecto, a diferencia de la versión simple que usaban ambos spies.

**Nota práctica para Dragón, repitiendo la lección del Crash #5:** una vez que una tecla deja de responder a mitad de sesión así, el juego puede seguir viéndose completamente vivo mientras ese pedazo específico de estado de Lua queda trabado — reiniciar el juego antes de la próxima prueba es la forma más segura de que nada del cuelgue se arrastre.

Verificado con `luaparse`, desplegado. **Plan de prueba:** repetir CTRL+H→"4"→Feed sobre varios Pals salvajes distintos en una sola sesión (siempre construcción nueva ahora) y confirmar que CTRL+H sigue respondiendo cada vez, no solo la primera — además de revisar si `[FOUR-KEY-SPY]` (ahora async) captura cada "4" real esta vez. Detalle completo en `hook-points.md` ("Hundred-and-seventieth pass").

## Continuación 144 (2026-09-05): CRASH REAL — presionar "4" muy cerca de CTRL+H hace que corran dos sistemas reales al mismo tiempo sobre el mismo Pal

Dragón tuvo un crash real (Fatal Error, dump de Windows) pegando "ctrl+h primero, después 4" — rápido. El log confirma exactamente por qué: `CanOpenPlayerActionMenu` (la señal real de que "4" se procesó) apareció ENTREMEDIO de las propias líneas de nuestro CTRL+H, mientras `do_test_direct_feed_dispatch` todavía estaba corriendo. El sistema real de sustitución de "4" (`RADIAL-REDIRECT`, un segundo `CanOpenPlayerActionMenu`) siguió disparando casi al mismo tiempo que nuestra propia llamada a `pal:OnSelectedOrderWorkerRadialMenu(parameter)` — y ahí el log se corta y aparece el crash. Dos sistemas reales construyendo UI nativa sobre el MISMO Pal al mismo instante — no la llamada en sí (que ya completó limpio muchas veces sola).

**Arreglado:** movida la declaración de `radialMenuActionWindowOpen` (la bandera real que ya existía, verdadera durante toda ventana real de menú de "4") a mucho antes en el archivo, para poder leerla desde `do_test_direct_feed_dispatch`. Ahora, justo antes de la llamada riesgosa, si esa bandera está en `true` (el menú real de "4" está activo en ESE momento), la función aborta con un mensaje claro en vez de competir con él.

**Límite honesto del arreglo:** esto solo cubre una dirección — CTRL+H corriendo primero, "4" presionado durante su ejecución (que es justo lo que pasó). No puede detectar el orden inverso (si "4" se presiona primero y CTRL+H llega unos milisegundos después, antes de que su propio estado se asiente). Por eso la regla real de seguridad para probar sigue siendo: nunca presionar "4" y CTRL+H muy pegados — esperar un par de segundos entre uno y otro, sin importar el orden.

Verificado con `luaparse`, desplegado.

## Continuación 145 (2026-09-05): RESUELTO — CTRL+H funciona solo de verdad; toda la confusión de "4" era un retraso de varios segundos en la UI, nada más

Dragón esperó como se le pidió, sin tocar "4", y el resultado cierra la pregunta del todo, con los dos spies funcionando y timestamps sin ambigüedad. La llamada de CTRL+H a `OnSelectedOrderWorkerRadialMenu` devolvió "ok" en ~170ms — pero el popup real no se volvió clickeable hasta unos 3.6 segundos después (Dragón estimó "unos 10 segundos", el mismo fenómeno, solo percibido más largo). El feed real disparó con un simple click de `LEFT_MOUSE_BUTTON` — sin ninguna actividad de "4"/`FOUR` cerca, confirmado por `[FOUR-KEY-SPY]` (ahora funcionando confiable, async) Y por `InputSpy`. Una presión de "4" 8 segundos DESPUÉS disparó un segundo feed completamente separado, por el sistema de aproximación de siempre, sobre el mismo Pal — una acción no relacionada que hizo después, no parte del mecanismo real.

**Las propias palabras de Dragón dan la explicación real:** "so all this time its just that ctrl+h has a terrible delay, which made me think it activated by the 4 radial menu." Exacto. Nunca hubo una dependencia real del sistema Otomo/"4" — tanto la teoría de "desbloquea el pipeline del Otomo" (mía) como la de "hizo al Pal salvaje elegible como propio" (de Dragón) partían de la premisa falsa de que "4" era realmente necesario. Nunca lo fue. El mecanismo real es tan simple como sugería el hallazgo original de Ghidra desde el principio: el "abrir" de `SelectedFeedingItem` no tiene chequeo de propiedad y no necesita nada más — CTRL+H solo abre el popup real, punto. El único hueco real era que este proyecto nunca contempló un retraso de varios segundos en la construcción de la UI antes de asumir que una llamada "no hizo nada".

**Arreglado:** los dos mensajes de log de CTRL+H (el anuncio de Init() y el mensaje post-llamada) ahora dicen explícitamente que funciona solo, avisan del retraso de varios segundos antes de que el popup sea visible/clickeable, y avisan de no presionar "4" mientras se espera (riesgo real de crash, Continuación 144). Sin cambios de lógica esta pasada — fue un arreglo de mensajes/documentación, el mecanismo ya estaba correcto.

Esto cierra la pregunta real y de meses en el corazón del punto 7 (comida real con inventario para Pals salvajes): **funciona, solo, vía CTRL+H, confirmado dos veces ahora con datos limpios y sin ambigüedad.** Pendiente para esta función: crédito de confianza/amistad todavía no conectado (Dragón dijo explícitamente "not yet"), y la protección contra el crash de la pasada anterior solo cubre una dirección de la interferencia con "4" — aunque ya que "4" está confirmado como innecesario, la regla práctica más simple y segura es: no presionar "4" cerca de CTRL+H para nada.

## Continuación 149 (2026-09-05): investigación del Kinship Peach — confirmado cero de amistad real, y CTRL+H reutilizado para la primera escritura de este proyecto sobre datos reales de inventario

Con el mecanismo real de Feed ya en vivo, Dragón lo probó directo para la pregunta del "Kinship Peach" que este proyecto arrastra desde la Continuación 34: alimentó a un Eikthyrdeer salvaje con su único Kinship Peach menor real por el menú "4" real, después lo acarició 6-7 veces hasta disparar una captura real sin esfera.

**ID real del ítem confirmado:** `AffectionFruit_02` — coincide con uno de los dos nombres candidatos encontrados en las tablas de ítems del juego desde la pasada ochenta y tres, ahora confirmado vía el mismo hook `[SLOT-USE-DIAG]` en vivo ya usado para las Berries.

**Contribución real de amistad del peach: confirmado matemáticamente cero.** Ningún `AddFriendShip` disparó cerca del momento del consumo (una brecha limpia de 16 segundos). El total real de puntos del Pal al capturar (70) se descompone exacto en 7×10 — coincide con los 6-7 acariciados reales que siguieron, cada uno acreditando +10 vía el mecanismo ya establecido (la acción real de Cuidar vanilla disparando independiente sobre el Pal salvaje sustituido, según la pasada ciento cincuenta y nueve). Sin residuo, sin salto sin explicar — el bonus real vanilla del peach, sea cual sea, no se aplica por este camino de consumo específico para un Pal salvaje todavía en pleno vínculo.

**Hallazgo aparte, no nuevo pero reproducido de nuevo con claridad:** el contador propio de interacciones de este proyecto solo logueó `"interaction #1"` pese a 6-7 acariciados reales acreditados — el mismo hueco ya documentado donde el propio gate de ocupado de `do_pet()` descarta casi cada presión mientras la animación real vanilla otorga crédito por un camino completamente separado. El total de puntos se mantuvo exacto (dispara bien el umbral de captura); solo el CONTEO de interacciones queda corto para acariciados que pasan por el menú real sustituido.

**Duplicar el ítem para más pruebas — usando el propio encuadre de Dragón:** en vez de tratar esto con el mismo rigor que la mecánica central de PalBonds ("ningún otro mod hace esto, lo peleamos nosotros"), señaló claramente que generar/duplicar ítems es distinto — ya está resuelto públicamente, así que incluso un intento fallido no cuesta nada (hay un mod ya funcional de respaldo). Investigué una referencia real y de código abierto (`starpoem17/PalWorld_ItemConsole` en GitHub) en vez de adivinar — su propia función de duplicar ítems (`item.drop`, explícitamente "crea un pickup en el mundo... sin consumir inventario") resultó estar respaldada por un DLL nativo completo en C++ (`native/PalItemNativeDrop/`, compilado vía CMake, exponiendo un global de Lua propio `PalItemNativeDrop`) — una categoría de ingeniería mucho más pesada y distinta que todo lo hecho en este proyecto, que es 100% Lua. No era el atajo "debería ser más fácil" que parecía a primera vista.

**El camino real y mucho más simple que sí aplica:** Dragón no necesita un generador genérico de ítems — ya tiene Kinship Peaches y solo quiere más de ese ítem específico. `find_best_food_slot()` (ya probada segura, ya usada para las Berries) encuentra el `PalItemSlot` real y vivo que tiene un ítem dado; escribir su campo `StackCount` es la misma categoría de escritura de campo plano ya hecha segura en otras partes de este archivo (`BaseCampId`, `IndividualHandle`, `resultType`) — solo que es la primera vez que se toca algo que es dato real y persistido de guardado, no estado efímero de UI/interacción.

**CTRL+H reutilizado de nuevo** (su trabajo anterior — probar el mecanismo de despacho directo — ya está confirmado y conectado permanentemente al menú "4" real, así que ya no necesita su propia tecla de prueba dedicada; el cuerpo viejo queda comentado, no borrado, según la costumbre de este proyecto): `do_test_multiply_kinship_peach()` encuentra el slot real con `AffectionFruit_02`, loguea el conteo real actual, y escribe un conteo objetivo conservador (10 — no un número extremo, ya que no se sabe el límite real de un solo stack de este ítem y esto es territorio genuinamente nuevo). Loguea antes y después de la escritura para que el resultado sea inequívoco de cualquier forma.

Verificado con `luaparse`, desplegado. **Plan de prueba:** presioná CTRL+H una vez, después revisá el inventario real en el juego — ¿el conteo del peach realmente muestra 10? ¿se ve/comporta normal (sin corrupción visual, sin crash, se puede seguir eligiendo/usando normal en un feed real)? Avisame exactamente qué ves, sea cual sea el resultado.

## Continuación 150 (2026-09-05): confirmado y arreglado — `RequestUseToCharacter` nunca decrementa para un objetivo salvaje, el mismo límite ya encontrado antes vía CTRL+J

Dragón subió el peach a 10 y corrió una prueba controlada de 6 feeds sobre un Tanzee Ignis salvaje nuevo (Berry, Berry, Peach, Peach, Berry, Peach). Los seis leyeron exactamente el mismo conteo previo al feed — Berries clavado en 110 las tres veces, peaches clavado en 10 las tres veces. Cero movimiento, no intermitente — un resultado negativo limpio y total.

**Esto no es nuevo — es el mismo muro que este proyecto ya golpeó y sorteó una vez, desde otro ángulo.** En el experimento de CTRL+J (pasadas ciento diecisiete/dieciocho), llamar `RequestUseToCharacter` directo sobre un Pal salvaje "decía que sí" pero nunca movía el stack, mientras la misma llamada sobre el Otomo propio funcionaba bien las dos veces. El nuevo camino de Feed del menú "4" real termina llamando a esta misma función por dentro, así que hereda el mismo no-op silencioso para un objetivo no propio.

**Esto también da una explicación real y unificada para la amistad faltante** (tanto del Eikthyrdeer como de este Tanzee): si la lógica del juego nunca trata el ítem como genuinamente consumido para un objetivo que no considera realmente propio, entonces cualquier lógica interna que otorgaría un bonus de amistad por ese consumo — incluyendo cualquier bonus específico del Kinship Peach — tampoco corre nunca. Mismo portón, los dos síntomas.

**Arreglado, reusando el mismo respaldo ya probado seguro en el viejo mecanismo de CTRL+J:** agregado un POST-hook sobre `RequestUseToCharacter` (el pre-hook de observación existente se queda igual, puro logging). Una bandera nueva a nivel de archivo, `pendingWildFeedTarget`, la pone `do_real_wild_feed_via_worker_menu` justo antes de su llamada riesgosa y la consume (una sola vez) el post-hook — solo actúa cuando está puesta, así que un feed normal a un Pal propio (que ya decrementa bien solo, confirmado con los feeds a Pals de party de esta misma sesión) nunca se toca dos veces. Cuando está puesta, el post-hook resta `UseNum` directamente del `StackCount` real del slot, logueando antes/después.

Verificado con `luaparse`, desplegado. **Plan de prueba:** repetir un Feed real salvaje (cualquier ítem) por el menú "4" y confirmar que el conteo real del inventario ahora sí baja de a uno, con una línea `[MANUAL-DECREMENT]` mostrando los números antes/después.

## Continuación 146 (2026-09-05): conectado el mecanismo real al menú "4" de verdad, reemplazando la aproximación para Feed salvaje

Dragón pidió directo: "lets add it to the menu, lets see how it works with the actual radial menu instead of ctrl + h." Conecté `OnSelectedOrderWorkerRadialMenu`/construcción de parámetro fresco (la misma forma de llamada ya probada de `do_test_direct_feed_dispatch`) dentro de `closeRadialMenuActionWindow` — la función que ya dispara la acción real cuando el menú "4" se cierra con un Pal salvaje sustituido y una instrucción decidida de "feed".

**Función nueva, `do_real_wild_feed_via_worker_menu`:** apunta a `cachedRedirectWildPal` (el Pal salvaje real que esta misma ventana de menú viene sustituyendo, no un reapuntado nuevo — el jugador puede no estar mirando al Pal para cuando el menú cierra), construye un parámetro nuevo siempre (nunca reusa — el cuelgue de la Continuación 143), escribe `IndividualHandle`/`resultType`, y llama a la función real. Devuelve `true`/`false` en vez de lanzar error, así la rama de Feed de `closeRadialMenuActionWindow` puede caer de vuelta a la aproximación vieja (`do_feed`) automáticamente si algo del camino real falla incluso al armarse — Dragón nunca se queda con silencio.

**Esto REEMPLAZA la aproximación para Feed salvaje, no corre junto a ella** — una vez que la llamada real funciona, `do_feed` no se llama también (a diferencia de CTRL+H, que siempre corría independiente de lo que hiciera "4"). Pet/Care vía "4" queda completamente intacto — ya pasa por la acción real de Cuidar y nunca fue parte de este problema.

**Chequeado a propósito, aunque la carrera exacta que causó el crash de la Continuación 144 no debería aplicar acá:** para cuando `closeRadialMenuActionWindow` corre, la secuencia de APERTURA propia del menú "4" (`CanOpenPlayerActionMenu`/`OpenSetup`) ya terminó del todo — el peligro de antes era específicamente nuestra llamada compitiendo con esa apertura, no existiendo durante un cierre. Agregué el chequeo de `radialMenuActionWindowOpen` igual, puramente como salvaguarda "no debería ser verdad acá, pero no vale la pena arriesgarse".

**Mismo comportamiento esperado de antes, ahora dentro del flujo real de Feed en vez de una tecla separada:** el popup real de elegir ítem puede tardar varios segundos en aparecer/volverse clickeable DESPUÉS de que el menú "4" ya se cerró visiblemente — no es un bug, ya confirmado dos veces.

Verificado con `luaparse`, desplegado. **Plan de prueba, primera corrida con cuidado:** alimentar a UN Pal salvaje vía el menú "4" real (apuntar, presionar "4", elegir Feed, dejar que el menú cierre normal) y fijarse en: (1) el popup real de elegir ítem apareciendo unos segundos después — elegir un ítem y confirmar que la animación/consumo pasa; (2) la animación VIEJA de aproximación NO debería pasar también — esto está pensado para reemplazarla del todo ahora; (3) si algo se ve mal, avisar de inmediato, igual que cualquier otro cambio de efecto real en este archivo.

## Continuación 147 (2026-09-05): bug propio — el chequeo defensivo de `radialMenuActionWindowOpen` disparaba SIEMPRE, bloqueando la llamada real por completo

Dragón probó y le tocó la aproximación vieja las dos veces — el popup real nunca apareció. El log mostró por qué de inmediato: `[REAL-FEED] ABORTING — the real "4" menu window is still marked open` disparó en ambos intentos. Suposición equivocada en el chequeo agregado la pasada anterior: `closeRadialMenuActionWindow` recién pone `radialMenuActionWindowOpen = false` DESPUÉS de llamar a la rama de Feed, no antes — así que la bandera está SIEMPRE en verdadero justo en el punto donde este chequeo nuevo corría, por diseño, siempre, sin excepción. El propio comentario decía "no debería pasar al cerrar" — nunca se comparó contra el código real de alrededor antes de agregarlo.

**También vale la pena notar por qué el chequeo nunca hacía falta acá para empezar:** el crash de la Continuación 144 vino de dos eventos de tecla SEPARADOS e independientes (un CTRL+H suelto compitiendo con un "4" suelto) ejecutándose al mismo tiempo. Este punto de llamada es distinto de raíz — `do_real_wild_feed_via_worker_menu` corre de forma sincrónica, en una sola cadena de llamadas, como continuación directa de la MISMA lógica de cierre del propio "4". No hay ningún segundo disparador independiente involucrado, así que ese peligro específico de reentrada nunca estuvo presente acá.

**Arreglado:** se sacó el chequeo por completo en vez de intentar parchear su condición — no protegía contra nada real en este punto.

Verificado con `luaparse`, desplegado. **Plan de prueba, igual que la pasada anterior:** alimentar a un Pal salvaje vía el menú "4" real y confirmar que el popup real de elegir ítem ahora sí aparece (con el retraso conocido de unos segundos) en vez de caer a la aproximación siempre.

## Continuación 148 (2026-09-05): CONFIRMADO FUNCIONANDO — Feed real con inventario para Pals salvajes, en vivo en el menú "4" real, sin retraso esta vez

Dragón probó y confirmó un éxito completo y limpio: apuntó "4" a un Sheepball salvaje, eligió Feed, el selector real de ítems se abrió, eligió una Berry, y el consumo/animación real siguió — a través del menú real del juego, no una tecla de prueba aislada. Esta es la respuesta real y permanente al punto 7 (comida real con inventario para Pals salvajes), ahora en vivo en el flujo normal de interacción, no un experimento aparte.

**Notable y vale la pena recordar: sin el retraso de varios segundos esta vez**, a diferencia de cada prueba anterior con solo CTRL+H. Explicación probable, sin confirmar todavía: pasar por el flujo real de "4" significa que el sistema de UI/input del juego ya está "caliente" (un menú recién estaba abierto, cerrándose) justo cuando dispara `OnSelectedOrderWorkerRadialMenu`, mientras que CTRL+H la llama completamente en frío, desde un estado de input parado/inactivo — suficientemente plausible como para no tratar el retraso anterior como una propiedad fija del mecanismo mismo.

**Estado actual del punto 7:** el mecanismo es real, confirmado dos veces en dos contextos distintos (tecla aislada, y ahora el menú "4" en vivo), y reemplaza la aproximación de gesto+Happy para Feed salvaje específicamente (Pet/Care sin tocar). El crédito de confianza/amistad para este camino sigue sin conectar, según el "not yet" explícito de Dragón — el consumo real y la animación funcionan los dos, pero este camino de Feed específico todavía no otorga ningún progreso de vínculo. Eso queda como el próximo paso real cuando Dragón lo pida.

## Continuación 137 (2026-09-05): la conclusión de "callejón sin salida" fue prematura — Dragón cuestionó bien, y la prueba real nunca llegó a probar nada sobre BaseCampId

Dragón probó CTRL+H (copiar BaseCampId), reportó "dont think it worked" y pegó un volcado de Live View mostrando instancias VIVAS del menú de Worker. Revisé el log con marcas de tiempo exactas y escribí una primera conclusión: "BaseCampId no alcanza, tercer callejón sin salida confirmado." Dragón preguntó directo: "are you sure they're actual dead ends?" — y tenía razón en dudar.

**Lo que en realidad muestra el log, revisando el hook nativo `[MENU-WATCH]` (ya existía desde hace muchas pasadas):** en TODA la sesión hubo un solo enganche real de apuntado nativo (`ActionType=4` con un `TargetInteractiveObject` real) — el del ChickenPal que YA era trabajador real, a las 00:11:16, ANTES de cualquiera de los dos intentos de CTRL+H. Ninguno de los dos intentos de BaseCampId logró ese enganche nativo. Y peor: después del segundo intento (00:12:22, sobre ese mismo ChickenPal que ya era trabajador — no aporta nada nuevo de todos modos), Dragón nunca volvió a presionar "4" — no hay ningún dato de menú para ese segundo intento.

**Esto significa que la única prueba que importaba (el Sheepball genuinamente salvaje, 00:12:06) nunca llegó a la pregunta real.** El juego nunca registró "estás apuntando a la esfera de interacción de este Pal específico" — así que "4" cayó al menú genérico del jugador por el motivo YA documentado desde las pasadas 76-77 (sin enganche nativo → menú de respaldo siempre), sin relación con si BaseCampId alcanza o no. Declarar esto un callejón sin salida fue prematuro — nunca se verificó si la propia condición previa de la prueba (un enganche nativo real sobre el objetivo) se cumplió antes de sacar una conclusión sobre lo que pasa después de esa condición.

**Queda genuinamente abierto, con al menos tres hipótesis sin descartar:** (1) precisión de apuntado — nuestra propia tolerancia (`find_targeted_pal`, 500 unidades/25°) es más laxa que el cono/rango real de la esfera nativa; (2) idea de Dragón — quizás haga falta estar dentro del radio real de una base activa, sin probar; (3) quizás las esferas de Pals salvajes simplemente nunca estén construidas para ofrecer `ActionType=4` en absoluto — una propiedad fija de construcción, no un chequeo en vivo, en cuyo caso ningún campo (BaseCampId, WorkAssignId, lo que sea) importaría.

**Próxima prueba real, sin código nuevo** (el hook `[MENU-WATCH]` ya alcanza): apuntar lo más preciso y cerca posible a un Pal salvaje, SIN ningún cambio de BaseCampId todavía, presionar "4", y revisar si `StartTriggerInteract ActionType=4` dispara con ese Pal como objetivo. Si nunca dispara ni en esta prueba base, descarta BaseCampId de raíz (el problema sería estructural, no de datos). Si sí dispara, recién ahí repetir con la copia de BaseCampId. Detalle completo, con la corrección explícita, en `hook-points.md` ("Hundred-and-sixty-fourth pass").

## Continuación 136 (2026-09-04): un campo real y mucho más seguro para membresía de base — CTRL+H reutilizado otra vez

Dragón hizo una observación real que cambió el rumbo: un Pal puede estar en una base sin ningún trabajo asignado, e incluso NPCs humanos pueden pertenecer a una base. Eso sugiere que "soy miembro de esta base" es un concepto separado y más simple que "tengo un trabajo específico" (el objeto `WorkAssignId`/`UPalWorkAssign` que se descartó por riesgoso la pasada anterior).

Confirmado real en el header del juego: `FGuid BaseCampId` vive en `UPalIndividualCharacterParameter` — el MISMO objeto que `get_individual_parameter(pal)` ya devuelve en cada interacción — completamente separado de `WorkAssignId` (que vive en otra clase distinta). Copiar un ID de base REAL (leído de otro Pal ya confirmado miembro de una base real) sobre este campo es mucho más seguro que la idea anterior: no se construye ningún objeto nuevo, no se le roba el trabajo a nadie — mismo principio de "reusar un valor real, nunca inventar uno" ya probado en este proyecto.

**Implementado:** CTRL+H reutilizado de nuevo (su trabajo anterior — probar que la llamada directa a SelectedFeedingItem era insegura — ya está confirmado y cerrado). Busca un Pal real con BaseCampId real cercano, copia ese valor sobre el Pal apuntado, loguea antes/después. Verificado con `luaparse`, desplegado.

**Prueba pendiente:** con al menos un Pal real puesto en una base cerca, apuntar CTRL+H a otro Pal (salvaje idealmente) y presionar una vez, después presionar "4" sobre ese mismo Pal — ¿se abre el menú de Worker (Pet/Feed/ShowStatus/AddToParty) en vez del menú del jugador? Detalle completo en `hook-points.md` ("Hundred-and-sixty-third pass").

## Continuación 151 (2026-09-05): prueba real de FPS destapó dos bugs en vivo — un hook de investigación muerto disparando por cualquier cosa cercana, y NPCs humanos (comerciantes) cayendo en el sorteo de personalidad

Durante una prueba real de FPS (PresentMon, modded vs. modless, tarea aparte sin relación al código del mod), Dragón desglosó los datos por modo de presentación y señaló, aparte, dos sospechosos concretos del lag real que sentía jugando: "the constant check of what im looking at (for wild pals), which probably triggers when i even look at a tree" y "a confirmation that runs over and over for nearby pals... I often see it in the console." En vez de adivinar, se sacó el log real (`palbonds-live.log`) de esa misma sesión y se desglosó por volumen de etiqueta.

**Confirmado #1 — `[MENU-WATCH]`, 1048 de 6384 líneas (16%).** Es el hook de observación de `PalInteractComponent:StartTriggerInteract`/`EndTriggerInteract` de la pasada trece — dispara con `ActionType=2/3/4` sobre CUALQUIER objeto interactuable cercano (árboles, almacenamiento, estructuras, no solo Pals), exactamente como describió Dragón. Se revisó si algo seguía dependiendo de él: `lastAimedInteractTarget` (escrito ahí en cada `ActionType=4`) ya no se lee en ningún otro lado del archivo — el mecanismo real de alimentar salvajes (pasadas 168/173) usa `cachedRedirectWildPal` en su lugar, así que esa escritura estaba muerta. El bloque `WORKASSIGN-DIAG` adentro corría un escaneo completo de `find_targeted_pal()` (el mismo escaneo de ~35-50ms ya documentado como costoso) en cada "4" real, investigando una teoría de elegibilidad por `WorkAssignId` ya superada por el hallazgo de BaseCampId (pasada 163) — esa investigación ya terminó. Confirmado muerto de verdad, no solo ruidoso — comentado por completo (cuerpo viejo preservado, según la costumbre de este proyecto).

**Confirmado #2 también, pero más pesado que una simple "confirmación."** `[DIAG-CREATE]`/`[DIAG-PANEL]`/`[DIAG-TRUST]`/`[DIAG-LABEL]` de `Indicator.lua` — ~2437 líneas juntas. Las muestras reales muestran que no es un chequeo barato — es construcción completa de widgets (`StaticConstructObject`, `AddChildToCanvas`, `SetPosition`, `SetSize`, resolver el actor real del Pal, crear una etiqueta de texto) pasando de cero unas 315 veces en una sesión de 3 minutos en la base (~1.75/seg). El juego reutiliza un pool compartido de widgets de barra de vida entre los Pals visibles en cada momento (confirmado desde las pasadas 45/46) — cada vez que uno se reasigna a un Pal distinto, este mod reconstruye toda la barra de confianza + etiqueta desde cero. Es funcionalidad real y querida (no código muerto), así que no se tocó esta pasada — necesita una decisión de diseño real (limitar la frecuencia de reconstrucción, cachear más agresivo por ID de Pal, actualizar solo lo que cambió en vez de reconstruir todo) antes de tocarla, queda pendiente para que Dragón decida.

**Aparte, algo más serio encontrado jugando de verdad tras el grindeo:** al llegar a un pueblo, los comerciantes (NPCs humanos) también estaban cayendo en el sorteo de personalidad — uno salió "warlike" y le disparó de verdad. `EXCLUDED_FROM_ROLLING` (pasadas 153/162) debía evitar exactamente esto, pero solo funcionaba comparando el nombre real del preset resuelto del individuo (`VillageNPC`/`Kill_All`/`Boss`/`NotInterested`) — y esa resolución depende de toda la cadena `AISensorComponent`/`AIResponsePreset`, ya documentada en otras partes de este archivo como frecuentemente fallida. Un NPC humano casi seguro nunca resuelve un preset de la misma forma que un monstruo, así que se colaba en silencio por la tabla de exclusión (llave nil/incorrecta) directo al sorteo.

Dragón también pidió revisar el mod de referencia "Pal Analyzer" (nunca investigado a fondo) buscando una técnica de menor lag para mostrar info de Pals. Se extrajeron sus strings (`.uasset`/`.uexp`, sin `strings` real disponible en este entorno — se usó `grep -aoE '[ -~]{5,}'` como sustituto, esta vez con éxito) y salieron dos cosas nuevas y útiles a la vez:

- Su diseño es basado en "hover" (lo que estás mirando ahora mismo), no un escaneo de todos los Pals visibles: `HoveredCharacter`, `IsValidHoverCreature`, `BreakHitResult`, `GetCameraLocation/GetCameraRotation` — hace un line-trace desde la cámara y solo construye info para lo que está bajo la mira, nunca un widget por cada Pal visible a la vez. Por eso estructuralmente no tiene el costo de reconstrucción por-Pal-visible que sí tiene `Indicator.lua` — es un diseño genuinamente distinto, no una implementación más barata del mismo. No adoptado esta pasada (el objetivo de `Indicator.lua` es mostrar la barra en TODOS los Pals cercanos a la vez, no solo el que estás mirando — rediseñar a solo-hover cambiaría qué hace la función, no solo cómo se construye — queda señalado para que Dragón opine antes de perseguirlo).
- Su grafo de Blueprint distingue explícitamente con `IsPalMonster`/`IsWildNPC` antes de tratar algo como una criatura real. Confirmado en vivo contra el header dump nativo del juego: `bool UPalUtility::IsPalMonster(const AActor*)` y `bool UPalUtility::IsWildNPC(const AActor*)` — la MISMA clase estática de confianza que este proyecto ya usa (`get_pal_utility()`, para `GetIndividualCharacterHandleByActor`/`PalCaptureSuccess`/etc.). A diferencia de la cadena de preset, esto recibe el actor crudo directo — sin `AISensorComponent`, sin objeto de preset, nada que pueda fallar en silencio como la exclusión actual.

**Arreglo, en `Personality.lua`:** nueva `is_confirmed_pal_monster(palActor)` — llama `utility:IsPalMonster(palActor)`, devuelve `false` (no es monstruo) ante CUALQUIER fallo, en vez de dejarlo pasar al sorteo — misma convención de fallo seguro que `Capture.IsAlreadyOwned` (una exclusión de más solo cuesta variedad de personalidad; una inclusión de más es un NPC humano vuelto hostil, mucho peor). Conectado como gate incondicional en `GetOrInitState`, revisado ANTES de la tabla de nombres de preset — atrapa NPCs humanos incluso cuando su preset nunca resuelve, justo el escenario que dejó pasar al comerciante. La exclusión vieja por nombre de preset se queda como segunda capa (sigue sirviendo para Bosses reales, que SÍ pasan `IsPalMonster` pero también deben quedarse "normal").

Verificado con `luaparse` en ambos archivos, desplegado. **Prueba pendiente:** volver a un pueblo con comerciantes/NPCs humanos — ninguno debería rolear otra cosa que "normal" de ahora en adelante, resuelva o no su preset. La quita de `[MENU-WATCH]` debería notarse como una baja real de volumen de log/consola la próxima sesión; el costo de reconstrucción de la barra de confianza (punto 2 arriba) sigue sin tocar y sigue siendo una fuente de lag real, pendiente de una decisión de diseño.

## Continuación 152 (2026-09-05): tres correcciones directas de Dragón — NotInterested vuelve a estar disponible, corregí mi lectura del Pal Analyzer, e InputSpy por fin apagado

Tres correcciones de Dragón sobre lo dicho en la Continuación 151, ninguna una simple confirmación.

**1. Sacada la exclusión de NotInterested.** Dragón: "that means we can include notinterested pals once more... now that you've found that separation, then we can use that instead." Esa entrada (pasada 162) solo existía como proxy indirecto para atrapar NPCs humanos por nombre de preset. Con `is_confirmed_pal_monster` ya filtrando `GetOrInitState` de forma directa e incondicional antes de siquiera llegar a esa tabla, el proxy queda redundante — sacado. Un monstruo real cuyo default de especie sea NotInterested ya puede rolear una personalidad real de nuevo. VillageNPC/Kill_All/Boss se dejaron intactos (Boss es una categoría real de monstruo — Alphas — que Dragón quiere excluida sin importar la pregunta humano/monstruo).

**2. Mi afirmación anterior sobre "Pal Analyzer solo muestra el Pal apuntado" estaba mal.** Dragón cuestionó con evidencia real: una captura del mod de referencia muestra varios Pals con su cuadro de análisis abierto a la vez. Revisando de nuevo los strings extraídos (no solo confirmando mi lectura anterior) aparecieron `SphereTraceMultiForObjects` (un trace que golpea VARIOS objetos en un radio, no un solo objetivo bajo la mira) más un `Map_Add`/`Map_Find`/`Map_Keys`/`Map_Values` real (casi seguro un mapa Pal→su widget) y una variable de loop. Mi lectura anterior solo había revisado las funciones de un solo trace y se detuvo ahí. Conclusión corregida, más útil que la anterior: la técnica real probablemente sea mantener SU PROPIO mapa Pal→widget, creando un widget una sola vez por Pal y reusándolo/reposicionándolo mientras siga cerca, en vez de apoyarse en el pool de widgets de barra de vida que el JUEGO mismo recicla (que es de donde viene el costo real de `Indicator.lua`). No implementado todavía — queda como opción concreta para cuando se decida qué hacer con el punto 2 pendiente (reconstrucción de la barra de confianza).

**3. `InputSpy.lua` por fin desactivado.** Su propio encabezado ya decía cuándo apagarlo: "once the radial-menu question is closed" — cerrada desde la pasada 173 (el mecanismo real de alimentar vía menú ya confirmado funcionando de punta a punta). Dragón notó que seguía disparando en cada WASD/click en un fragmento fresco de consola y preguntó directamente por qué seguía ahí — sin buena razón para mantenerlo. `InputSpy.Init()` comentado en `main.lua`. Esto además explica por qué el desglose de volumen de la pasada anterior no lo detectó: sus líneas usan la etiqueta de módulo `[PalBonds/InputSpy]` en vez de una segunda etiqueta entre corchetes tipo `[TAG]`, y el grep usado para rankear por volumen solo capturaba corchetes con `[A-Za-z0-9_-]+` — se lo perdió por completo.

Verificado con `luaparse` en los tres archivos, desplegado. **Prueba pendiente:** el volumen de log/consola debería bajar todavía más ahora que InputSpy está apagado, sumado a la quita de MENU-WATCH de la pasada anterior.

## Continuación 153 (2026-09-05): implementada la técnica del Pal Analyzer para la barra de confianza — reusar en vez de reconstruir en cada reciclado de gauge

Dragón aprobó probar la técnica encontrada en la pasada anterior: "lets try using that then, see if the lag drops more." Implementado en `Indicator.lua`: `install_trust_bar` ahora resuelve el Pal real ANTES de construir nada, y si ese Pal ya tiene una barra viva en `trackedBars` (ahora indexado por ID de Pal cuando se conoce, no por identidad del widget de gauge), una nueva `reparent_existing_bar` mueve los widgets YA CONSTRUIDOS al panel real del nuevo gauge (`RemoveChild` + `AddChildToCanvas`, ambos confirmados reales en el `UMG.hpp` de este juego) en vez de reconstruir desde cero — los objetos persisten, solo cambia su panel/posición. Esto evita `StaticFindObject`/`StaticConstructObject`/la búsqueda de la clase de la etiqueta para un Pal que ya se está siguiendo, que según los números reales de la pasada anterior (315 construcciones completas en 3 minutos, muchas más que los Pals realmente distintos cerca de una base) es el caso común, no la excepción.

Si el ID del Pal no se puede resolver todavía al crear el gauge (la carrera ya conocida con `BindFromHandle`), cae al comportamiento viejo (construir fresco bajo una llave temporal) — y el reintento ya existente en `update_trust_bars`, cuando resuelve el actor más tarde, ahora también intenta promover esa entrada a su llave real de Pal ID, para que un reciclado FUTURO del mismo Pal también pueda reusarla. Las promociones se juntan durante el loop y se aplican DESPUÉS (insertar una llave nueva en una tabla mientras se recorre con `pairs()` no es seguro en Lua, aunque borrar una existente sí lo es).

Verificado con `luaparse`, desplegado. **Prueba pendiente:** una sesión de base ocupada como la que dio el número de 315 — revisar si aparecen líneas `[DIAG-CREATE] REUSED` y si las construcciones completas bajan de verdad, junto con una baja real de lag sentida.

## Continuación 154 (2026-09-05): investigación real para el balance — curva real de amistad por rango recuperada, toggle fácil/balanceado implementado, corrección sobre do_pet(), diagnóstico en vivo pendiente para los últimos dos valores

Dragón pidió 4 cosas para poder empezar el balance: un toggle fácil/balanceado, qué datos se pueden leer de un Pal, la curva real de puntos por rango de amistad (ya se había conseguido una vez, nunca se guardó), y los valores reales de los Kinship Peach.

**Corrección sobre do_pet().** Dije que estaba confirmado muerto basándome en un grep por el string literal `RegisterKeyBind.*F9` que se perdió el binding real — `PET_KEY = "F9"` y el registro real es `RegisterKeyBind(Key[PET_KEY], ...)`, una referencia por variable que el grep literal no pudo encontrar. F9 sigue vivo y sigue llamando a `do_pet()` directo. El rastreo del bloqueo por el gate de ocupado del jugador sigue siendo correcto, pero solo para el caso específico de que `do_pet()` se llame DESDE `closeRadialMenuActionWindow` (el flujo de Cuidar del menú "4") — ahí la acción real vanilla ya ocupó el slot de acción del jugador para cuando corre. Llamado directo por F9 (sin ninguna acción vanilla real recién disparada), el jugador normalmente no está ocupado, así que `do_interaction` sí puede tener éxito ahí. O sea: muerto solo en el camino del menú "4", no muerto en general.

**Datos reales disponibles de un Pal**, leídos directo de `FPalIndividualCharacterSaveParameter` (el mismo campo plano ya usado con seguridad en otras partes para `OwnerPlayerUId`): `Level`, `Rank` (rango de talento) más `Rank_HP`/`Rank_Attack`/`Rank_Defence`/`Rank_CraftSpeed`, `Talent_HP`/`Talent_Melee`/`Talent_Shot`/`Talent_Defense` (IVs), `Exp`, `Hp`/`MaxHP`, `IsRarePal`, `Gender`, el propio `FriendshipPoint`, y más. Todos campos escalares planos, mismo patrón de lectura seguro ya usado en todo este proyecto.

**Curva real de puntos por rango de amistad — recuperada con repak contra `Pal-Windows.pak`, decodificada a mano del binario crudo.** `DT_FriendshipRankTable` (struct `FPalFriendshipRankDataRow { int32 FriendshipRank; int32 RequiredPoint; }`) es diminuta (263 bytes) — se volcó en hexadecimal y se decodificaron a mano los pares int32 little-endian. Valores reales, Rango → Puntos requeridos: 1→6000, 2→13000, 3→21000, 4→30000, 5→40000, 6→55000, 7→80000, 8→110000, 9→150000, 10→200000. **Esto está lejísimos de nuestro propio `CAPTURE_AT_FRIENDSHIP_POINT = 55`** — el rango 1 solo ya necesita 6000 puntos reales. Queda como una decisión de diseño real para Dragón: seguir con la escala propia del mod (más chica y rápida, la actual) o atarse de verdad a la curva real de vanilla (mucho más lenta, pero "auténtica").

**Valores reales de Petting/Kinship Peach — NO se pudieron fijar de forma estática, quedan como diagnóstico en vivo.** Se encontró la clase real de constantes de balance (`UPalGameSetting`, con un campo dedicado `FriendshipPoint_Petting` real junto a `_AutoIncrementOtomo`/`_AutoIncrementActiveOtomo`/`_AutoIncrementWorker`/`_Starvation`/`_Sick`/`_Dead`/etc.), pero sus valores por defecto de Blueprint no serializan el nombre de ese campo en su propio asset — probablemente heredado de otro lado (un config .ini o una base distinta). De igual forma, la clase de datos estáticos del Kinship Peach no tiene un campo con nombre obvio de amistad — probablemente un campo genérico reusado (`FloatValue1` es candidato) cuyo significado depende del tipo de ítem. En vez de seguir adivinando de forma estática, se agregó `run_balance_diagnostic_once()` en `Interaction.lua` — corre una sola vez, automático, al iniciar: lee los campos reales de `UPalGameSetting` directo, y resuelve los datos estáticos reales de `AffectionFruit_01`/`AffectionFruit_02` (vía `UPalUtility.GetItemIDManager()` → `GetStaticItemData()`, ambos confirmados reales) volcando todas sus propiedades para encontrar cuál campo realmente tiene el bono de amistad. Sin efecto de juego, sin tecla — solo necesita un lanzamiento normal del juego para producir los números en el log.

**Toggle fácil/balanceado — implementado.** `Trust.lua` ahora tiene `EASY_TEST_MODE` (por defecto `true`) como la única bandera que controla `INTERACTIONS_TO_START_FOLLOWING`/`PASSIVE_FRIENDSHIP_PER_GAIN`/`DAMAGE_FRIENDSHIP_PENALTY`/`CAPTURE_AT_FRIENDSHIP_POINT`, cada uno ahora dividido en un par `EASY_*`/`BALANCED_*`. Los números `BALANCED_*` son placeholders a propósito (idénticos a `EASY_*` por ahora) — los valores reales son decisión de Dragón una vez que el balance tenga los datos de arriba para trabajar.

Verificado con `luaparse` en ambos archivos, desplegado. **Próxima sesión:** con solo lanzar el juego una vez deberían aparecer las líneas `[BALANCE-DIAG]` con el valor real de Petting y el volcado real del Kinship Peach — no hace falta ninguna acción más.



---

# Appended 2026-09-11: the rest of the narrative history

Everything below was moved out of `CLAUDE.md` on 2026-09-11, when that file was
rewritten to be a compact working document. Nothing was summarised or deleted —
this is the original text of the old "Estado actual", "Proximos pasos" and
Continuacion 155 to 180 sections, in their original order.

Read this only when you need the exact detail of an old decision. The current
state of the project lives in `CLAUDE.md`, and the technical pass-by-pass log
lives in `docs/hook-points.md`.

---

## Estado actual

**🎉 HITO ALCANZADO HOY (2026-09-01): se puede acariciar un Pal salvaje de verdad, sin que el juego se caiga.** Probado en vivo contra un Lamball común y un Chikipi ya agresivo, presionando la tecla varias veces seguidas sobre cada uno — 0 crashes en 14 intentos. Secuencia real confirmada: el jugador hace el gesto de estirar la mano (animación real del juego), se suma Friendship real (`AddFriendShip`), y el Pal responde con su animación de felicidad — y ya no se puede "spamear": si el jugador o el Pal están en medio de otra animación, la tecla simplemente no hace nada, igual que en el juego real.

**Camino hasta llegar ahí — 3 crashes reales en el proceso, ya resueltos:** Un `Debug_CaptureNewMonster`-style approach fue descartado pronto; en cambio, se intentó forzar animaciones reales llamando `PlayActionByType` directo desde Lua, lo cual causó 3 caídas distintas del juego. Sospechas iniciales (una acción sincronizada mal configurada, un Pal dormido interrumpido) resultaron ser pistas parcialmente falsas. La causa real, encontrada recién con un sistema de log propio a prueba de crashes (`Logger.lua`, que escribe y fuerza a disco cada línea al instante, porque el log normal de UE4SS se pierde entero cuando el juego se cae de golpe): una función (`GetSaveParameter()`) que copiaba una estructura entera de 880 bytes con arrays internos, usada solo para leer un dato chico (el GUID del dueño). Copiar algo así entre Lua y el juego es frágil y corrompía memoria. Se sacó esa llamada y se lee el dato directo del objeto en vez de copiar toda la estructura — eso solo bastó para que el mismo código que antes se caía siempre, ahora funcione siempre.

**Investigación con el SDK nativo de UE4SS (2026-09-01):** se activó el generador de SDK nativo de UE4SS (`Dumpers` → `Dump CXX Headers`), que reconstruye headers C++ de todas las structs/clases nativas del juego. Respondió:
- **Pregunta 3 (trust/friendship existente): RESPONDIDA.** `FriendshipPoint`, en runtime vía `UPalIndividualCharacterParameter:GetFriendshipPoint()` / `:AddFriendShip(valor, bool)`.
- **Pregunta 5 (ID estable por individuo): RESPONDIDA.** `FPalInstanceID`.
- **Pregunta 4 (captura sin esfera): pistas fuertes, sin probar en vivo todavía.**
- Pregunta 6 sigue parcial.

Detalle técnico completo (los 3 crashes, el log a prueba de fallos, la causa real, y los nombres exactos de cada función) en `docs/hook-points.md`.

**Dos bugs reales encontrados y confirmados arreglados (mismo día, sesión siguiente):** (1) el mod estaba acariciando sin querer al propio personaje del jugador (`PalPlayerCharacter` es en sí una subclase de `PalCharacter`, y la comparación para excluirlo no funcionaba de forma confiable en Lua) — esto explicaba varios reportes confusos anteriores ("acariciar el aire", saltos raros de friendship). (2) doble otorgamiento de friendship: cada acariciada real disparaba `AddFriendShip` dos veces (una nuestra, otra como efecto secundario de la propia animación "Happy" del juego) — se sacó la llamada explícita del mod y ahora se apoya solo en el efecto del juego, que ya es la cantidad correcta. Ambos confirmados arreglados en una sesión de prueba en vivo completa (Gumoss, Chikipi x3 con incrementos limpios de 0→10→20, guardia anti-spam funcionando).

**Limitación nueva encontrada (no arreglada, no urgente):** los jefes grandes (ej. Mammorest) son efectivamente imposibles de apuntar — el chequeo de distancia/ángulo usa un solo punto (la raíz del actor), que en un jefe de ese tamaño puede estar lejos de donde el jugador realmente está mirando. Los Pals de tamaño normal funcionan bien.

**Alimentar (F10) agregado:** mismo mecanismo que acariciar (F9), reutilizando el gesto de "estirar la mano" real del juego (`HumanFeeding`, en vez de `HumanPetting`) y la misma reacción "Happy" ya probada. Es una aproximación: el alimentar real del juego elige un ítem de comida específico del inventario primero (encontramos las funciones reales para eso, `SelectedFeedingItem`/`UPalAction_FeedItemToCharacter`, pero no están conectadas todavía) — por ahora F10 no consume ítems ni varía el monto según la comida.

**Primer intento de "que no huya" tras interactuar:** encontramos campos reales en el SDK (`APalAIController.TargetPlayers`/`TargetNPCs`, `HateSystem:ChangeHate()`) y se intenta limpiar el "objetivo" del Pal justo después de una acariciada/alimentada exitosa. Esto es un experimento, no una solución confirmada — el campo real de "personalidad/disposición" (Pregunta 1 de DESIGN.md) sigue sin encontrarse. En paralelo se agregó un volcado de propiedades de solo lectura (mismo método que usa un mod ya incluido en UE4SS para inspeccionar objetos) filtrado por palabras clave ("warning", "escape", "curious", etc.) que se registra en el log cada vez que se interactúa con éxito — la idea es que unas pocas pruebas reales (un Pal que sí huye vs. un Daedream que no) nos den el nombre real del campo en vez de adivinar.

## Próximos pasos

1. **Confirmar que revertir `SetActiveAI` arregló la animación:** acariciar/alimentar a un Pal que ya sigue debería volver a mostrar la animación real (no solo la sonrisa "Happy").
2. **Confirmar el daño con los nuevos logs:** golpear al propio Pal que sigue, y dejar que otro Pal salvaje lo golpee — revisar las líneas `[DAMAGE-WATCH]` en el log para confirmar quién aparece como atacante en cada caso, y que la penalización real aplicada sea -25 (no -50).
3. Con `SetActiveAI` fuera de la ecuación, ver si un Pal que llega a rango 0 por daño ahora sí reacciona en tiempo real (huye o pelea) en vez de quedarse congelado hasta que restauramos su IA después del hecho.
4. **Encontrar qué Blueprint implementa `GetIndicatorInfo` para un `PalCharacter` genérico** (el próximo paso concreto de la Pregunta 2/acariciar-alimentar salvaje) — buscar en FModel bajo otros nombres de clase base de Pal, no "PalCharacter.uasset" (no existe con ese nombre exacto).
5. **Seguimiento real de Otomo — la secuencia real de "cambiar de Pal activo" ya está CONFIRMADA EN VIVO (2026-09-02, continuación 7):** observando al juego real hacerlo (no adivinando), quedó claro que el cambio de Pal activo NO usa las funciones que se habían encontrado antes (`ActivatePalByHandle`/`ActivateCurrentOtomo` nunca se dispararon, en dos sesiones de prueba completas) — usa una clase de Blueprint específica del jugador, `BP_OtomoPalHolderComponent_C`, con esta secuencia real, confirmada 4 veces seguidas: `holder:InactivateCurrentOtomo()` seguido de `holder:ActivateOtomo(slot, transform, éxito)`. Falta un solo eslabón real antes de animarse a probar algo con un Pal salvaje: qué función se dispara cuando un Pal se UNE por primera vez a la party (una captura real) — `AddOtomoHandleToFreeSlot` nunca se disparó para el jugador en nada de lo probado hasta ahora (cambiar de Pal, acariciar, alimentar, abrir la Palbox), solo una vez para un NPC. Próximo paso, todavía sin ningún riesgo nuevo: pedirle a Dragón que capture un Pal salvaje nuevo de forma normal (con esfera, como siempre) con el sistema de observación activo, para ver si esa función se dispara y con qué datos — recién ahí se habría cerrado el último hueco real antes de proponer un experimento de verdad sobre un Pal salvaje.
6. El seguimiento aproximado actual (tick de 1.5s, sin suprimir la IA salvaje) sigue siendo el sustituto mientras el punto 5 no se intente.
7. Pendiente aparte, sin tocar todavía: Pregunta 1 (personalidad/disposición real — confirmado que `TargetPlayers`/`HateSystem` NO es el campo correcto), Pregunta 4 (captura real sin esfera — el disparador ya funciona, falta la llamada real), y el ítem kinship peach (necesita el FName real del ítem).




## Historial archivado (Continuación 1 a 154)

**2026-09-06:** este archivo había crecido a más de 460KB — superando el límite de lectura de una sola llamada, un riesgo real de que una sesión futura no viera contenido importante. El historial narrativo completo de las sesiones 2026-09-01 a 2026-09-05 (Continuación 1 a 154) se movió, sin resumir ni borrar nada, a `CLAUDE-archive.md`. **No hace falta leerlo para continuar el trabajo** — la lista "EMPEZAR ACÁ" de arriba y las continuaciones recientes de abajo (155 en adelante) ya tienen todo lo necesario. Consultarlo solo para el detalle exacto de una decisión/hallazgo viejo. Mismo criterio aplicado a `docs/hook-points.md` / `docs/hook-points-archive.md`.

## Continuación 155 (2026-09-05): crash real en el diagnóstico de balance — un CDO pasado como WorldContextObject, arreglado con el jugador real

El diagnóstico de la pasada anterior crasheó de verdad al siguiente lanzamiento — pero no sin antes lograr los números reales de `UPalGameSetting` (Petting=30, AutoIncrementOtomo=10, AutoIncrementActiveOtomo=50, AutoIncrementWorker=1, Min=-15000, Max=250000, Starvation/Sick/Dead=-100, SleepOnSide=100). El crash pasó justo después, antes de cualquier línea del lado de los ítems.

**Causa real:** `utility:GetItemIDManager(utility)` — se pasó el propio CDO (`Default__PalUtility`) como argumento `WorldContextObject`. Un CDO no es un objeto real en el mundo — no tiene un `UWorld` real al que resolver. La función nativa probablemente intenta `WorldContextObject->GetWorld()` por dentro y desreferenció basura. Arreglado usando `FindFirstOf("PalPlayerCharacter")` (el mismo actor real ya usado en todo este archivo) en su lugar. Se agregó logging antes/después de cada llamada nueva, para que si algo vuelve a fallar, el log diga exactamente cuál.

**Sobre la pregunta de Dragón:** `GetStaticItemData` lee la definición ESTÁTICA del ítem, no su inventario personal — tanto `AffectionFruit_01` como `AffectionFruit_02` deberían volcarse sin importar cuál de los dos tenga realmente en su inventario.

Verificado con `luaparse`, desplegado. **Prueba pendiente:** lanzar el juego una vez más — ahora debería pasar el punto donde crasheaba antes y mostrar el volcado real de ambos niveles del Kinship Peach.

## Continuación 156 (2026-09-05): segundo crash real en el diagnóstico de balance — un string de Lua pasado como FName, arreglado con FindOrAddFName

La prueba de Dragón llegó más lejos (el arreglo del WorldContextObject funcionó, `GetItemIDManager` tuvo éxito) pero crasheó de nuevo — rastreado exacto gracias al logging antes/después ya agregado: la línea "about to call GetStaticItemData(AffectionFruit_01) NOW" apareció sin ninguna línea de "returned" después — el crash pasó adentro de esa llamada.

**Causa real:** se pasó un string plano de Lua directo donde la función nativa espera un `FName` real (`GetStaticItemData(const FName StaticItemId)`). Primera vez en este proyecto que se pasa un string de Lua DENTRO de una llamada nativa como argumento FName — todos los usos anteriores de FName solo LEÍAN uno de vuelta, nunca construían uno para mandar.

**Arreglo real, encontrado en los propios mods incluidos de esta instalación de UE4SS** (no adivinado): `BPModLoaderMod`/`ConsoleEnablerMod` construyen un FName real vía `UEHelpers.FindOrAddFName(string)` antes de pasarlo a cualquier llamada nativa. Agregado `UEHelpers` a los requires de `Interaction.lua` y envuelto el ID del ítem con `FindOrAddFName` antes de la llamada.

Verificado con `luaparse`, desplegado. **Prueba pendiente:** este es el tercer intento de este diagnóstico después de dos crashes reales — si vuelve a fallar, lo honesto es parar de iterar a ciegas sobre esto y repensar el enfoque, no seguir adivinando formas de llamada nativa una por una.

## Continuación 157 (2026-09-05): CONFIRMADO — valores reales de ambos Kinship Peach, cierra la investigación de balance

Tercer intento, sin crash. Datos reales confirmados:

| | AffectionFruit_01 (completa) | AffectionFruit_02 (menor) |
|---|---|---|
| `FloatValue1` (probable bono de amistad) | 20000.0 | 2000.0 |
| Rareza | 3 | 1 |
| Precio | 30000 | 20000 |
| RestoreSatiety | 10 | 1 |
| RestoreSanity | 100 | 10 |

Cada estadística escala exactamente 10x entre los dos niveles — confirma que `FloatValue1` (un campo genérico reusado, ya que no existe un campo dedicado de amistad en `UPalStaticItemDataBase`) es de verdad el bono real de amistad, con una magnitud (2000/20000) que encaja naturalmente en la misma escala de la curva real de rango encontrada dos pasadas atrás (6000 en rango 1, hasta 200000 en rango 10) — no es un número chico arbitrario de UI. Corrección sobre la estimación de Dragón: la proporción real es 10x, no ~5x.

Cierra la investigación de balance de esta sesión — ya hay números reales para: Petting vanilla (30), las cuatro tasas de ganancia pasiva, las cuatro penalizaciones, la curva completa 1-10 de rango de amistad, y ambos niveles del Kinship Peach.

## Continuación 158 (2026-09-05): implementado el balance real — números pequeños de vanilla durante el vínculo, umbral escalado por nivel, bono de golpe al capturar

Diseño real de Dragón, refinado en vivo tras la pasada de investigación: en vez de números grandes propios (1000/2000/7000/21000 por interacción) manejando la barra directamente, el vínculo salvaje usa cantidades reales y chicas, a escala vanilla (Petting ≈30, Feed ≈60, ambos niveles del Kinship Peach con sus valores reales ya encontrados), y el multiplicador por diferencia de nivel escala el TAMAÑO de un umbral chico (`BONDING_TRIGGER_THRESHOLD_BASE = 100`, el propio número de ejemplo de Dragón) en vez de cada ganancia individual — un Pal de nivel mucho más alto necesita una barra proporcionalmente más grande llena con los mismos números reales, no números más grandes. Al llegar a ese umbral, un bono de una sola vez (`CAPTURE_BONUS_TARGET_POINT = 21000`, Rango 3 real de vanilla) empuja el total real del Pal hacia arriba antes de la captura real, así que el Pal recién capturado arranca con un vínculo real significativo en vez de un total ínfimo.

**Por qué esto es más simple y de menor riesgo que el primer borrador:** Pet/Play no necesitan ninguna sobreescritura del otorgamiento real de vanilla — el efecto secundario interno de Happy se aplica intacto, igual que siempre. Feed (hoy cero crédito real para Pals salvajes) recibe un otorgamiento explícito basado en el monto real de Petting en vez de un número redondo inventado. Solo la comparación de UMBRAL y el bono de captura de una sola vez son código nuevo — ninguna forma nueva de llamada nativa, nada parecido al riesgo de los crashes de FName/CDO de la fase de investigación misma.

**Trust.lua:** `Trust.ComputeLevelMultiplier(palActor)` — lee `SaveParameter.Level` del Pal y del jugador real (mismo campo, confirmado vía `IsPlayer`), devuelve 0.2/0.5/1/2/4 según la diferencia de nivel (los huecos entre los cinco puntos que dio Dragón caen por defecto en el nivel "más o menos igual" x1 — una interpretación, marcada como tal). Devuelve un 10x plano en cambio mientras `EASY_TEST_MODE` esté activo, por pedido explícito de Dragón. `get_bonding_threshold(pal)` = `BONDING_TRIGGER_THRESHOLD_BASE / multiplicador`, usado por `maybe_trigger_capture` y expuesto como `Trust.GetBondingThreshold` para la barra de Indicator.lua (antes leía una constante global plana — ahora es real por Pal). `maybe_trigger_capture` ahora también aplica el bono de captura (nunca reduce un total ya más alto, ej. por un peach) antes de llamar a `Capture.OnTrustMaxed`. `OnFollowerDamaged` ganó un parámetro `attackerIsPlayer` — un golpe normal sigue constando `DAMAGE_FRIENDSHIP_PENALTY` (reescalado a -150), pero un golpe del JUGADOR resetea el total real a 0 y huye de inmediato ("traición"). La ganancia pasiva pasó de un monto plano cada N ticks a `PASSIVE_FRIENDSHIP_PER_TICK = 10` cada tick (~1.5s) — un punto de partida real a escala vanilla, el número que Dragón piensa retocar en vivo (considerando 200/seg tras probar) — ya NO escalado por el multiplicador de nivel.

**Interaction.lua:** `FEED_FRIENDSHIP_BASE = 60`, `KINSHIP_PEACH_LESSER/FULL_FRIENDSHIP_BASE = 2000/20000` (los valores reales ya encontrados). El post-hook de `RequestUseToCharacter` (ya el lugar confirmado donde cae un Feed salvaje real) ahora también lee el ID del ítem consumido, otorga el monto correspondiente vía `AddFriendShip`, y llama a `Interaction.OnWildPalPetted` — nada de esto existía antes (Feed salvaje real otorgaba cero confianza hasta ahora).

**Dejado a propósito sin tocar, señalado para Dragón:** `INTERACTIONS_TO_START_FOLLOWING` (sigue en 5 interacciones crudas, todavía no el disparador por porcentaje de barra discutido antes) — la causa raíz ya diagnosticada (el contador de interacciones no incrementa de forma confiable ahora que Pet/Feed pasan mayormente por las acciones reales de vanilla) sigue sin arreglar. Esta pasada solo implementó los VALORES de punto reales que Dragón especificó; el rediseño del disparador de seguimiento es una pieza aparte, todavía no accionada.

Verificado con `luaparse` en los tres archivos, desplegado. **Prueba pendiente:** vincularse con un Pal cerca del propio nivel (~x1) y ver la barra llenarse con Pet/Feed normales; probar un Pal de nivel mucho más bajo para confirmar que la barra llena más rápido; confirmar que un Kinship Peach completo captura de un solo golpe a un Pal de nivel igual o menor; confirmar que el FriendshipPoint real del Pal queda en 21000 justo al capturar; probar un golpe del jugador sobre un Pal siguiendo para el reset de traición.

## Continuación 159 (2026-09-05): multiplicadores exactos de Dragón + números base refinados

Dragón dio los tramos exactos del multiplicador de barra (4x/2x/1x/0.5x/0.25x) y preguntó si traducían bien la idea original de multiplicador de ganancia (0.2x/0.5x/1x/2x/4x). Revisado: cuatro de cinco son recíprocos exactos, el quinto (el tramo más alto) redondea 1÷0.2=5 a un más limpio 4 — traducción correcta.

**Un giro de dirección atrapado al implementar:** `Trust.ComputeLevelMultiplier` ahora devuelve directamente un multiplicador de TAMAÑO DE BARRA (número más grande = barra más grande/difícil), la imagen espejo del enfoque anterior. Esto significó que `get_bonding_threshold` pasó de dividir a multiplicar, y — fácil de pasar por alto — el override plano de `EASY_TEST_MODE` también tuvo que invertirse: el "10x más fácil durante pruebas" de Dragón ahora significa devolver `1/10`, no `10`, ya que un multiplicador de tamaño de barra más grande ahora hace las cosas MÁS DIFÍCILES, no más fáciles.

**Números base refinados, todas cifras exactas de Dragón:** `BONDING_TRIGGER_THRESHOLD_BASE` 100→500, `PASSIVE_FRIENDSHIP_PER_TICK` 10→5, los Kinship Peach pasaron de los valores reales crudos de vanilla (2000/20000) a números limpios en base a la nueva barra de 500 (250 menor / 500 completo — la peach completa ahora otorga exactamente una barra completa de un solo uso a nivel igual). Pet/Play, Feed, penalización de daño y traición ya estaban correctos de la pasada anterior.

Verificado con `luaparse`, desplegado.

## Continuación 160 (2026-09-05): lag real atrapado por Dragón — el multiplicador de nivel se recalculaba cada tick para cada Pal visible, arreglado con un caché permanente

Dragón reportó lag terrible, sobre todo al entrar a áreas nuevas, y diagnosticó la causa él mismo correctamente: `Trust.ComputeLevelMultiplier` se llamaba de cero en CADA tick para CADA Pal con barra de confianza visible (la barra de Indicator.lua, no solo los Pals con los que realmente se interactúa) — cada llamada hacía una lectura real de componente en el Pal Y un `FindFirstOf` fresco más otra lectura de componente en el jugador, cada vez — un costo que escala directo con cuántos Pals hay en pantalla.

**Arreglo, diagnóstico y solución propia de Dragón:** "it should be calculated on the interactions... maybe saved in the cache." El nivel de un Pal nunca cambia a mitad de sesión, así que el multiplicador ahora se cachea de forma PERMANENTE por Pal la primera vez que se calcula — cualquier llamada posterior es una lectura barata de tabla, no un cálculo fresco. Único riesgo real: si el jugador sube de nivel a mitad de sesión, los Pals ya cacheados se quedan con el multiplicador viejo — aceptado como un trade-off menor y raro contra una fuente de lag real y segura que escala con la cantidad de Pals.

Verificado con `luaparse`, desplegado.

## Continuación 161 (2026-09-05): sin fallback — el umbral de un Pal sin interacción real jamás se calcula, ni una sola vez

Dragón afinó más el arreglo anterior: incluso un solo cálculo (y una escritura de caché) por Pal sigue siendo trabajo desperdiciado para la mayoría de los Pals, que aparecen y desaparecen en el fondo sin que el jugador se les acerque nunca. `Trust.GetBondingThreshold` ahora revisa si existe una entrada real de `Trust.State` (creada solo por una interacción real) ANTES de tocar `ComputeLevelMultiplier` — sin entrada, devuelve `nil`, no una constante por defecto. `Indicator.lua` trata `nil` como "nada que mostrar todavía" y devuelve 0 directo, sin dividir ni hacer ninguna lectura de nivel. Cero cálculo, cero escritura de caché, para cualquier Pal sin interacción real.

Verificado con `luaparse`, desplegado.

## Continuación 162 (2026-09-05): el arreglo grande — la barra de confianza ya no se construye para un Pal sin interacción real

Dragón hizo la pregunta estructural correcta: ¿la barra se construye para todo Pal que aparece, o solo para los que se miran? Rastreado: `Indicator.lua` escanea el contenedor nativo de gauges del juego (`Canvas_Root`) cada 2 segundos y construye/actualiza una barra propia para CADA Pal que el juego mismo muestra con gauge nativo — todo Pal cercano/visible, no solo los interactuados. En un área concurrida son 15-20+ Pals, todos con lectura y refresco periódico para siempre.

**Decisión de Dragón: solo construir/actualizar barras para Pals con interacción real registrada** (el mismo principio ya aplicado al multiplicador de nivel, ahora extendido a la existencia misma de la barra). `Trust.HasBondingState(palActor)` — una lectura de tabla plana, sin resolución de actor/componente — filtra `install_trust_bar` antes de cualquier trabajo de widget. No marca el gauge como "ya resuelto" al saltarlo por esta razón — sigue revisando en escaneos futuros (barato) para que un Pal interactuado después sí reciba su barra.

Verificado con `luaparse`, desplegado.

## Continuación 163 (2026-09-05): DAMAGE-WATCH y DIAG-PANEL recortados, y una corrida de prueba dedicada cerró los cuatro hilos abiertos de OtomoWatch

Dragón pegó un fragmento real de consola y preguntó qué era todo eso. Dos hallazgos reales revisando el código directo, no adivinando: `[DAMAGE-WATCH]` (Trust.lua) registraba CADA golpe real del juego entero, sin relación con ningún Pal en vínculo — el propio comentario del código lo admitía, de la Decimoctava pasada, cuando el único objetivo era confirmar que el hook disparaba. Arreglado moviendo el log adentro del mismo chequeo que ya usa la lógica real de penalización (`State[defenderName].isFollowing`). `[DIAG-PANEL]` (Indicator.lua) tenía el mismo problema — logueaba cada cambio del pool nativo de gauges del juego, información de una investigación de estructura ya cerrada desde la pasada cincuenta y uno. Recortado, dejando intacto el escaneo funcional (necesario para instalar las barras).

**Corrida de prueba dedicada, pedida por Dragón para cerrar OtomoWatch de una vez:** una sola sesión con una captura real por esfera, una captura real sin esfera, y un rescate real de jaula. Resultado, los cuatro hilos abiertos cerrados:
- `ABP_PalCaptureJudgeObject_C`/`[CAPTURE-JUDGE]`: nunca disparó en ninguno de los tres eventos — confirmado de nuevo que es exclusivo del flujo de Arena/desafío. **Sacado.**
- `ABP_CaptureWire_C`: tampoco disparó nunca, su propósito nunca se confirmó. **Sacado.**
- `PawnOtmoIsPartyOtomo`/`[PARTY-DIAG]` (Interaction.lua): revisado 17 veces, incluyendo sustituciones reales de Pal salvaje por el menú "4" — `FindAllOf(PalPlayerPartyPalHolder)` encontró 0 instancias todas las veces. Confirmado muerto para el alcance real de este proyecto (sin Arena). **Sacado** el llamado; la función queda comentada por si algún día se retoma soporte de Arena.
- `ABP_ReturnPalEffect_C`/`[PRISM-SPY]`: la sorpresa real. Cada instancia esta sesión coincidió casi al segundo con un evento `[INACTIVATE-CURRENT]` (cambiar de Pal activo), nunca con ninguna de las capturas ni con el rescate de jaula — tumba la teoría de "haz de luz de captura" de las pasadas cuarenta y cinco/cuarenta y seis, que se basó en una coincidencia de tiempos en una prueba temprana. Misterio cerrado, con una respuesta distinta a la esperada. **Sacado** (ya no queda nada que investigar ahí).
- `UBP_ActionUnlockCagePalLock_C`: disparó justo al abrir la jaula, como se esperaba — confirmado real. **Se queda.**

Verificado con `luaparse` en `Trust.lua`, `Indicator.lua`, `OtomoWatch.lua` e `Interaction.lua`, desplegado en el juego real. Sin cambio de comportamiento para nada que Dragón use — todo esto era instrumentación de investigación ya respondida.

## Continuación 164 (2026-09-05): personalidad visible restaurada, el bug de la captura instantánea de la Petallia arreglado, y los triggers reales por porcentaje de barra implementados

Dragón reportó tres cosas después de la corrida de prueba de OtomoWatch: (1) el arreglo de la barra de confianza (Continuación 162, solo para Pals interactuados) se llevó puesta sin querer la etiqueta de personalidad — la quiere visible en TODO Pal salvaje desde lejos, incluso sin interactuar, y mencionó que a futuro le gustaría exponer esto como una opción real de encendido/apagado en una interfaz de configuración; (2) capturó a su Petallia con un Kinship Peach menor y la Pal desapareció al instante, sin ninguna animación real (ni de alimentar, ni de comer, ni de felicidad); (3) preguntó si los triggers por porcentaje de barra (>10% personalidad cambia a friendly, +50% empieza a seguir) ya estaban implementados — no lo estaban.

**Arreglo 1 — personalidad visible restaurada, desacoplada de la barra de confianza.** `install_trust_bar` ahora construye la etiqueta de personalidad para TODO Pal con gauge, siempre, sin condición — solo la barra real de confianza sigue exigiendo `Trust.HasBondingState` (una interacción real), preservando el arreglo de lag de la Continuación 162. Esto necesitó arreglar dos bugs reales que habrían aparecido en la próxima prueba: `reparent_existing_bar` exigía que la BARRA ya existiera para poder mover solo la ETIQUETA (una entrada solo-etiqueta nunca se podía reusar, así que se construía una duplicada en cada reciclado de gauge) y `update_trust_bars` exigía `entry.bar:IsValid()` sin condición cada tick (con `bar` ahora legítimamente `nil`, esto habría descartado y reconstruido cada entrada solo-etiqueta, cada tick). Ambos arreglados. Se agregó además `try_upgrade_entry_with_bar`: en cuanto un Pal solo-con-etiqueta tiene su primera interacción real, la barra real se construye ahí mismo, sin esperar a que su gauge se recicle.

**Arreglo 2 — la causa real de la desaparición instantánea, encontrada en el código:** `Trust.maybe_trigger_capture` llamaba a `Capture.OnTrustMaxed(pal)` (la captura real) de forma completamente sincrónica, apenas se cruzaba el umbral — sin ningún respeto por si había una animación real todavía reproduciéndose. No es un bug exclusivo del peach — cualquier cruce de umbral podía en teoría cortar una animación — el peach solo lo hizo pasar siempre, al dar un solo salto grande, en vez de ocasionalmente con ganancias graduales de acariciado. **Arreglo, según la preferencia explícita de Dragón (esperar a que la animación real termine, no un delay fijo, porque puede variar según el Pal y "se siente más natural en el flujo del proceso de domesticación"):** ahora se usa `ActionComponent:ActionIsEmpty()` — la misma función real ya probada en este proyecto (el propio gate de ocupado de `do_interaction`, tanto del jugador como del objetivo) — revisada cada 500ms hasta que reporta libre, con un tope de seguridad generoso de 20 segundos (algunas animaciones reales, como las de descanso de Play, se vieron correr 20+ segundos) antes de capturar de todos modos. Si el `ActionComponent` del Pal ni siquiera se puede leer, cae de inmediato al número de respaldo explícito de Dragón: un delay fijo de 5 segundos.

**Arreglo 3 — los dos triggers reales por porcentaje de barra, implementados, reemplazando los mecanismos viejos por completo (a pedido explícito de Dragón, no como respaldo):**
- `Trust.lua`: nuevas constantes `FOLLOW_TRIGGER_RATIO = 0.5` y `FRIENDLY_TRIGGER_RATIO = 0.2` (números exactos de Dragón — ajustó el "10%" original a 20% en la misma conversación), ambas fracciones del mismo `get_bonding_threshold(pal)` que ya usa todo el resto del sistema. Revisadas en `Trust.OnInteractionSucceeded` justo después de leer el punto real — el tick pasivo no necesita su propia copia de este chequeo, ya que solo procesa Pals que YA están siguiendo, lo cual por construcción solo puede pasar después de que el trigger de 50% ya disparó por el camino de interacción.
- `Personality.lua`: `Personality.OnSuccessfulInteraction` (el viejo "escape → friendly" de un solo uso, solo en la primera interacción) fue renombrada y generalizada a `Personality.MaybeBecomeFriendlyByBar(palId, palActor)` — se sacó la restricción de "solo si es escape", ya que el nuevo trigger aplica desde cualquier disposición inicial. Se llama desde `Trust.OnInteractionSucceeded` (que tiene el ratio real) en vez del viejo punto de llamada en `Interaction.lua`, que se eliminó.

El viejo contador crudo `INTERACTIONS_TO_START_FOLLOWING = 5` (ya señalado como poco confiable desde la pasada 132) fue retirado del todo, según instrucción explícita de Dragón de reemplazar, no mantener como respaldo.

Verificado con `luaparse` en `Indicator.lua`, `Trust.lua`, `Personality.lua` e `Interaction.lua`, desplegado en el juego real. Progreso recalculado: Sistema de personalidad 75%→80% (etiqueta siempre visible + WON-OVER generalizado) y Sistema de confianza 65%→75% (triggers reales por barra + bug de captura instantánea arreglado) — total del proyecto 81%→82%.

**Prueba pendiente:** alimentar un Pal salvaje con un Kinship Peach por el menú "4" real y confirmar que la animación de comer/feliz se reproduce antes de que desaparezca; por separado, acariciar/alimentar un Pal hasta pasar el 20% de su barra y confirmar que su etiqueta cambia a "friendly", y seguir hasta el 50% para confirmar que empieza a seguir, sin necesitar cinco interacciones exactas.

## Continuación 165 (2026-09-05): prueba real de los 4 arreglos de la Continuación 164 — uno confirmado funcionando, tres bugs reales encontrados y diagnosticados (dos a fondo, uno parcial), ninguno arreglado todavía

Dragón hizo una corrida de prueba real cubriendo los cuatro puntos de la Continuación 164 y reportó punto por punto, más pegó un fragmento grande de log crudo. **No se cambió código en esta pasada — solo investigación, detenida a mitad de camino por un "wait stop here" explícito de Dragón antes de escribir cualquier arreglo.** Esta entrada documenta el estado exacto de la investigación para que quede claro dónde retomar.

**1. Etiqueta de personalidad — CONFIRMADO FUNCIONANDO.** Dragón: "thanks i see it again, very useful." El desacople de la Continuación 164 (etiqueta siempre visible) se sostiene en el juego real. Sin acción pendiente en este punto.

**2. Bug de desaparición instantánea — SIGUE PASANDO. El arreglo de la Continuación 164 (`ActionComponent:ActionIsEmpty()`) no funciona, y Dragón diagnosticó bien la razón antes de que se revisara el log:** "i asume its because you set it at the actionisempty(), which probably happens briefly between interactions, so its not a reliable method." Confirmado exacto por el log: el primer chequeo de `wait_for_animation_then_capture` (0.5ms después de empezar a esperar) ya reportó `idle == true`, mientras el diagnóstico de solo lectura de `Combat.lua` (`[FOLLOW-DIAG]`, ya existente desde la "pasada ochenta y seis") mostró, ~0.8ms ANTES, una acción de IA real y todavía corriendo (`BP_AIActionPairCall_FeedItem_C`). O sea: `pal.ActionComponent:ActionIsEmpty()` no refleja el mismo estado de "ocupado" que la acción real de varios pasos de Alimentar/comer/feliz — se libera casi al instante, sin relación con cuánto dura la secuencia real de animación.

**Arreglo identificado, sin implementar todavía:** cambiar la señal de espera en `wait_for_animation_then_capture` de "`ActionComponent:ActionIsEmpty()` da true" a "`pal.Controller:GetAIActionComponent():GetCurrentAction_BP()` da nil" — manteniendo la misma estructura ya armada (polling acotado vía `ExecuteInGameThreadWithDelay`, el mismo tope de seguridad generoso, y el respaldo explícito de Dragón de 5 segundos fijos si esta señal nueva resulta ilegible en algún Pal). Era el siguiente paso planeado cuando se detuvo la sesión.

**3. El trigger de seguimiento no produce comportamiento visible — SIN CONFIRMAR CON EVIDENCIA DIRECTA DE LOG para el caso específico que reportó Dragón.** Dragón: "didnt work, tested it with another petallia, reaching above 50%, she never followed, only roamed around with her usual AI." El único disparo real del trigger de seguimiento en el log pegado (`[Trust] bonding bar crossed 50% (ratio=1.04)` + `[Combat] ... marked as following (bonding)`) pasó en el MISMO instante en que también se cruzó el umbral de captura (un Kinship Peach empujando 50% y 100% de un solo salto) — sin ninguna ventana real donde el comportamiento de seguimiento pudiera haberse observado; no es evidencia de un bug en ese caso puntual. La segunda Petallia que describe Dragón (cruzando 50% sin capturar) no aparece en el log pegado.

Hipótesis de trabajo, SIN CONFIRMAR: el mecanismo real de seguimiento (`Combat.StartFollowing` marca `BondingState[key] = true`, después `tick_followers()` de `Trust.lua` reenvía `Combat.IssueFollowMoveOrder` → `controller:PalMoveToLocation(...)` cada ~1.5s) siempre estuvo documentado en este proyecto (incluyendo en los propios comentarios de cabecera de `Combat.lua`) como un "empujón" externo periódico que compite con la IA salvaje propia entre ticks, no un reemplazo real al estilo Otomo — es literalmente el punto 5 pendiente de Fase 2 en la lista propia de Dragón ("Seguimiento real durante el vínculo... [FOLLOW-DIAG] nunca se leyó"), de antes de esta sesión. Es posible que el trigger ya dispare bien (confirmado por log) pero el mecanismo de seguimiento en sí sea la misma aproximación débil ya conocida, no algo nuevo roto. Hace falta más evidencia de log de un caso donde el trigger dispare sin captura inmediata, o una decisión directa de Dragón sobre si reabrir ahora el trabajo pendiente de "seguimiento real durante el vínculo".

**4. El trigger de friendly dispara bien (estado registrado), pero la IA real nunca cambia — DIAGNOSTICADO EN DOS CAPAS, ninguna arreglada.** Dragón: "if a pal is running away (escape) or already fighting the player (warlike), and the interaction changes its personality to friendly, it still keeps doing what it was doing... this obviously defeats the process of changing their personality." Confirmado dos veces en el log: justo después de `[WON-OVER] ... crossed the friendly-trigger fraction of its bonding bar`, la línea siguiente las dos veces es `[WON-OVER] ... has no readable AISensorComponent — cannot swap its real AI, tracked disposition still updated`.

*Capa 1 (causa raíz del fallo puntual observado):* `Personality.MaybeBecomeFriendlyByBar` (renombrada/generalizada en la Continuación 164 desde la vieja `OnSuccessfulInteraction`, pero con su código interno de búsqueda de sensor heredado sin cambios) sigue llamando al viejo scan proactivo `find_sensor_component(palActor)`, ya documentado como poco confiable — el mismo mecanismo que este proyecto ya había reemplazado por un hook REACTIVO mucho más confiable (`on_sensor_select_response`, escuchando las llamadas reales del juego a `SelectResponseBySenses`) para el enforcement periódico por tier, desde la "Continuación 121". Ese arreglo nunca se trasladó a este camino de WON-OVER/trigger-por-barra, por eso sigue fallando casi siempre.

*Capa 2 (un problema más profundo encontrado al investigar la capa 1, sin resolver todavía):* aunque se cambiara `MaybeBecomeFriendlyByBar` para usar el sensor del hook reactivo, quedan dos obstáculos más, ambos solo leídos esta pasada:
- El dedup de `on_sensor_select_response` (`handledSensorKeys[sensorKey] = true`) se marca PERMANENTEMENTE la primera vez que el hook reactivo ve el sensor de un Pal — para cualquier Pal que ya estaba huyendo/peleando ANTES de que el jugador interactúe (exactamente los Pals de tier escape/warlike que está probando Dragón) esto casi seguro ya pasó durante el enforcement de su tier original. Esto bloquearía en silencio cualquier reintento de enforcement futuro para ese mismo sensor, incluso después de un cambio de disposición posterior.
- `try_enforce_personality_with_sensor(palActor, palId, sensor)` (la función compartida a la que llegan tanto el scan proactivo como el hook reactivo) lee `state.rolledTier` — el tier ORIGINAL tirado al aparecer — no `state.disposition`, el valor actual (posiblemente ya cambiado por WON-OVER). O sea que incluso con un sensor válido en mano, esta función compartida aplicaría el tier equivocado (el original), no "friendly" — nunca fue diseñada para ser consciente de un cambio de disposición. El código de enforcement propio e inline de `MaybeBecomeFriendlyByBar` sí apunta correctamente a `TIER_TO_DONOR_PRESET_CLASS["friendly"]` — el arreglo real necesita su propia fuente confiable de sensor, no simplemente enrutar a través de `try_enforce_personality_with_sensor` tal cual.

La investigación estaba a mitad de leer la lógica exacta de gate de `try_enforce_personality_with_sensor` (incluyendo un booleano separado `state.enforcementApplied`, marcado una sola vez para siempre en vez de por disposición objetivo) y todavía no se había encontrado dónde se llama periódicamente el scan proactivo `try_enforce_personality`, cuando se detuvo la sesión. No se diseñó ningún arreglo para este punto.

**Pendiente, nunca atendido esta pasada:** Dragón pegó aparte un fragmento grande de log crudo y pidió explícitamente "please explain me all this" — esa explicación en lenguaje simple nunca se dio; el log se usó directo como evidencia de causa raíz para los puntos 2-4 de arriba en su lugar. Sigue pendiente si lo vuelve a pedir en una sesión futura.

Sin cambios de código en esta pasada. El estado real desplegado sigue siendo exactamente el de la Continuación 164 (etiqueta confirmada bien; retraso de captura vía `ActionIsEmpty()` confirmado insuficiente; triggers de 50%/20% confirmados disparando bien a nivel de umbral, con las fallas de comportamiento de seguimiento y de swap real de IA de friendly descritas arriba todavía presentes). La entrada de la Continuación 164 debe leerse con esta corrección en mente — su arreglo de retraso de captura no se sostuvo en la prueba de seguimiento de Dragón.

## Continuación 135 (2026-09-04): rebalance de personalidad + exclusión de NotInterested real

Dragón confirmó que "unknown" resolvió el engaño — los Pals friendly ahora se ven friendly de verdad, y pidió no usar más fallbacks que escondan errores mientras el proyecto está en desarrollo ("no point in looking good for the user right now") — regla general a tener en cuenta de ahora en adelante para cualquier fallback nuevo.

**Rebalance pedido:** warlike_anyway y warlike_without_player bajaron de 10 a 5 cada uno, friendly subió de 20 a 30. Nueva distribución: normal 35 / friendly 30 / escape 10 / notinterested 10 / warlike 5 / warlike_anyway 5 / warlike_without_player 5 (suma 100).

**Nueva exclusión, confirmada posible y ya implementada:** Pals cuyo preset REAL ya es NotInterested (varios NPCs humanos lo usan) ahora quedan excluidos del roll igual que VillageNPC/Kill_All/Boss — se agregó `BP_AIResponsePreset_NotInterested_C` a `EXCLUDED_FROM_ROLLING`. Esto es completamente independiente de que "notinterested" siga siendo una opción real del roll ponderado para cualquier OTRO Pal (uno cuyo preset real sea friendly/escape/warlike/etc.) — son dos mecanismos separados que no chocan: uno decide "¿me toca tirar el dado?" (basado en el preset real actual), el otro es el resultado del dado en sí.

Verificado con `luaparse`, desplegado. Detalle en `hook-points.md` ("Hundred-and-sixty-second pass").

## Continuación 134 (2026-09-04): el fallback "friendly" era engañoso — reemplazado por "unknown"

Dragón preguntó directo si "friendly" se estaba usando como respaldo silencioso cuando la lectura de personalidad fallaba. Confirmado que sí: `PresetClassNameToDisposition` devolvía "friendly" tanto cuando no se podía leer el preset real como cuando el preset no estaba mapeado — y como esa lectura falla casi siempre (confirmado en el log de cada sesión), la etiqueta en pantalla mostraba "friendly" para la mayoría de los Pals con tier "normal" sin que fuera un dato real. Sumado al 20% que sí rolea "friendly" de verdad, más de la mitad de las etiquetas podían decir "friendly" sin serlo.

Pedido textual de Dragón: "from now on if it fails, show fail or show null or whatever it does normally, that way i know that its actually failing instead of thinking its a friendly pal."

**Arreglado:** las dos ramas de fallo ahora devuelven "unknown" en vez de "friendly" — un valor distinto, no uno de los 7 tiers reales, revisado contra todo lo que consume ese dato (nada se rompe, ni el chequeo de WON-OVER ni la etiqueta). Verificado con `luaparse`, desplegado. La próxima sesión probablemente muestre "unknown" en la mayoría de los Pals "normal" — no es una regresión nueva, es el estado real que antes se escondía. Detalle en `hook-points.md` ("Hundred-and-sixty-first pass").

## Continuación 133 (2026-09-04): CTRL+H causó un crash real — confirmado, arreglado (llamada sacada, no solo comentada)

La primera prueba real de Dragón de CTRL+H mostró algo nuevo: el juego siguió corriendo visualmente, pero saltó un aviso de crash igual, y varias cosas dejaron de responder (CTRL+H, CTRL+J, que segundos antes había funcionado bien).

**Confirmado con evidencia real, no con la descripción de Dragón solamente.** El log muestra la secuencia normal hasta "calling pal:SelectedFeedingItem(itemSlotId, 1) NOW" a las 23:01:39 — y la línea siguiente, que el propio `pcall` de esa llamada SIEMPRE debería imprimir (éxito o error de Lua, no importa cuál), nunca aparece. Existe un dump de crash real de Windows exactamente en ese mismo segundo (`crash_2026_09_04_23_01_39.1693134.dmp`). Y después de ese momento, el log de esa sesión no vuelve a registrar NINGUNA tecla presionada — ni siquiera el espía de WASD de `InputSpy`, que no tiene nada que ver con este código. `UE4SS.log` no muestra ningún "ensure"/"Fatal error" cerca — el crash ocurrió por debajo de lo que ese log de texto puede ver.

**Esto es peor que cualquier crash anterior del proyecto**: los 4 crashes previos siempre mataban el proceso entero (obvio, imposible de no notar) o tiraban un error de Lua atrapable. Este dejó el juego pareciendo sano mientras nada volvía a responder — mucho más difícil de detectar sin revisar el log real.

**Causa probable:** `SelectedFeedingItem` solo se había visto disparar antes como parte de una secuencia interna ya armada por el propio menú de Worker — llamarla en frío, sin esa preparación, probablemente lee algo que el flujo real siempre garantiza que existe. También podría ser una función "latente" (que nunca retorna sincrónicamente, solo por un delegado que el flujo real escucha) — cualquiera de las dos explica el "nunca vuelve" sin necesitar un crash duro.

**Arreglo:** la llamada real se sacó por completo del código (no solo comentada) — todo lo de antes (encontrar el slot real, leer ContainerId/SlotIndex, armar la tabla) se queda funcionando y logueando, CTRL+H ahora se detiene justo antes de la llamada peligrosa siempre. Verificado con `luaparse`, desplegado.

**Este camino (llamar `SelectedFeedingItem` directo) queda como tercer callejón sin salida confirmado**, junto a `RequestUseToCharacter` (atado al Otomo) y `SelectedFeed` (atado a la vtable). Lo único que queda por probar es lograr que el menú de Worker de verdad se abra apuntando a un Pal salvaje — un problema de elegibilidad de UI, no de seguridad de llamada nativa.

**Sobre los Pals amigables huyendo esa misma sesión:** sin evidencia que lo conecte al crash — el sistema de personalidad ya tiene un hueco real y separado (~95% de éxito, Continuación 130) que podría explicarlo solo. No se investigó más esta pasada.

Detalle completo en `hook-points.md` ("Crash #5"). **Prueba pendiente:** ninguna para este arreglo en particular (solo saca una llamada peligrosa) — antes de seguir con el menú de Worker, vale la pena que Dragón confirme que todo lo demás (F9/F10/Play/CTRL+K, la barra, personalidad) sigue andando normal después de reiniciar el juego, ya que esta sesión específica quedó con el estado interno roto.

## Continuación 132 (2026-09-04): causa raíz real de por qué Pet funciona y Feed/Play no — y un candidato genuinamente nuevo para comida real, nunca antes probado

Dragón hizo una prueba controlada y precisa (3 Pals salvajes, conteo exacto de acciones, valor final exacto de amistad) y pidió comparar contra el log real. El cruce fue exacto, sin excepciones: cada ganancia real de amistad equivale a +10 por cada Pet real, con Feed y Play aportando +0 en los 9 puntos de datos.

**Causa real, sacada de las líneas de log, no inferida:** para el Sheepball, 6 de 8 presiones reales (las 4 de Pet incluidas) quedaron descartadas por nuestro propio "player is already mid-action — ignoring press" antes de llegar siquiera a `Happy()`. Aun así la amistad real seguía subiendo +10 por cada pet. La explicación más consistente: la acción real de Cariciar del juego (no nuestro `do_pet()`) está disparando directo sobre el Pal salvaje sustituido a través del menú radial, totalmente independiente de nuestro propio gate — el mismo mecanismo de sustitución que ya existe hace semanas, solo que nunca se le había atribuido el mérito real de por qué Pet funciona. Feed nunca tiene esa ayuda real (confirmado hace semanas: el sistema profundo de comida nunca se activa para un Pal sustituido), así que depende 100% de nuestro propio `Happy()` — que, cuando sí logra dispararse, igual da 0. Esto tira abajo un supuesto viejo de este proyecto (que Happy() siempre otorga amistad como efecto secundario) — no es cierto para Feed/Play.

**Dragón rechazó, con razón, arreglar solo el número de hoy** (llamar `AddFriendShip` a mano para Feed/Play) — no construye hacia comida real (los kinship peaches). Preguntó si se podía aplicar el mismo truco de Pet a Feed — la respuesta, con evidencia ya generada por este mismo proyecto: no, ya se probó dos veces contra Feed específicamente (pasadas 123/124 de hook-points.md) y ambas confirmadas como callejón sin salida — el picker real de comida nunca se activa, muy probablemente porque el chequeo real es una llamada de vtable en C++ crudo, invisible para cualquier hook de Lua.

**La pregunta de Dragón sobre el menú de Worker abrió un candidato genuinamente nuevo.** Nunca se había probado alimentar a un Pal salvaje por el menú de Worker (el de apuntar, para Pals de base) — y su función real de consumo, `SelectedFeedingItem`, ya estaba confirmada por Ghidra SIN ningún chequeo de propiedad en su propio cuerpo (a diferencia de `RequestUseToCharacter`, que sí está atado al Otomo activo). Investigado y confirmado (documentación real de UE4SS, no adivinado): sí se puede construir una tabla de Lua anidada para pasar un struct como argumento — la misma categoría seguro, distinta a la que causó el Crash #4 (eso era un FName, no datos planos).

**Implementado: CTRL+H, tecla de prueba nueva** (las 4 teclas existentes están todas en uso activo, nada muerto para reusar esta vez). Llama `pal:SelectedFeedingItem(itemSlotId, 1)` directo sobre el Pal apuntado (salvaje incluido), reusando la técnica ya probada de CTRL+J para encontrar el stack real de Berries, y construyendo el struct nuevo solo con el mínimo necesario (el `ContainerId` real ya leído, nunca reconstruido desde cero). Verificado con `luaparse`, desplegado.

**Prueba pendiente:** apuntar CTRL+H a un Pal salvaje con al menos 1 Berry en el inventario, revisar si el StackCount baja de verdad y si el Pal reacciona — los hooks `[FOOD-DIAG]`/`[SLOT-USE-DIAG]` ya existentes confirmarán independientemente si esto realmente disparó la función real. Detalle completo en `hook-points.md` ("Hundred-and-fifty-ninth pass").

## Continuación 131 (2026-09-04): "¿siguen haciendo falta o es basura acumulada?" — auditoría real, un hook realmente muerto sacado

Dragón cuestionó directo mi reafirmación anterior de "esos fallos son normales, funcionan después" — con razón, no lo había verificado contra los datos reales de esa sesión.

**Verificado de verdad esta vez.** `[RADIAL-WATCH]` (respalda una función activa real): 14 éxitos reales confirmados, el primero en la ronda 5 — la reafirmación anterior era correcta para este caso, ahora con evidencia real. `[EMOTE-WATCH]` (los hooks para investigar el emote Cheer del jugador): **405 líneas esa sesión, cero éxitos, nunca.** Esa función ya se había abandonado dos pasadas después (crasheó dos veces, sacada del todo) pero nadie apagó los hooks que solo existían para eso. Esto sí era basura real.

**Saqué el loop de EMOTE-WATCH por completo** (comentado, no borrado). También revisé WORKER-BIND-FIX/OTOMO-GETTER-WATCH/MENU-WATCH antes de asumir que también eran basura — los tres están funcionando de verdad, solo con un formato de log distinto al patrón que probé primero.

Verificado con `luaparse`, desplegado. No hace falta prueba nueva para esto — solo saca volumen de log muerto, no cambia comportamiento. Detalle en `hook-points.md` ("Hundred-and-fifty-eighth pass").

## Continuación 166 (2026-09-05): los 3 bugs de la Continuación 165 arreglados con evidencia real del propio Pal.hpp del juego — ninguno confirmado en vivo todavía

Dragón dio permiso explícito para seguir con los tres puntos abiertos y aportó dirección directa en dos: corrigió mi diagnóstico del punto de personalidad (el swap sí funciona para un Pal idle — el problema real es solo con uno a mitad de huir/pelear) y pidió reabrir el seguimiento real durante el vínculo usando lo aprendido de los mods de referencia (PalFollowerTweaks/PalFunnelCharacter) y el propio `AIActionComponent` que `Combat.lua` ya había dejado como pista sin probar. Mid-sesión aportó además una pista propia y útil: el ícono "!" real del juego, que interrumpe visiblemente lo que un Pal está haciendo al notar al jugador acercarse — señalado como posible modelo para el problema de interrumpir una acción a mitad de camino.

Se localizó el `Pal.hpp` real en la instalación del juego de Dragón (`Palworld/Pal/Binaries/Win64/ue4ss/CXXHeaderDump/Pal.hpp`) y se grepeó directo para cada arreglo, en vez de razonar solo desde los resúmenes de pasadas anteriores.

**Bug 1 (captura instantánea) — arreglado tal cual el plan ya identificado.** `Trust.lua`'s `wait_for_animation_then_capture` ahora espera a `pal.Controller:GetAIActionComponent():GetCurrentAction_BP()` volviéndose nil, en vez del `ActionComponent:ActionIsEmpty()` ya confirmado poco confiable — misma estructura de sondeo cada 500ms, mismo tope de seguridad de 20s, mismo respaldo de 5s fijos si la cadena Controller/AIActionComponent no se puede leer.

**Bug 4 (friendly no interrumpe una acción en curso) — dos funciones reales y nunca antes llamadas, encontradas por grep directo:** `UPalAIActionComponent:AllCancelAction_Logic_HardScript_Reaction(Instigator)` (cancela la acción de IA en curso en los niveles de prioridad donde corren las decisiones normales de huir/pelear) y `UPalAISensorComponent:RequestSightCheckAsync(...)` (declarada justo al lado de `SelectResponseBySenses` — muy probablemente la función real detrás del "!" que señaló Dragón). Nueva `Personality.interrupt_and_resense()` llama a la cancelación primero y después al chequeo de sentidos fresco, imitando la secuencia real de "notar y girar" — conectada tras cada swap de preset exitoso en los tres puntos que pueden cambiar el tier de un Pal (`try_enforce_personality_with_sensor`, `MaybeBecomeFriendlyByBar`, `ForceTier`). Es de solo-mejor-esfuerzo: un fallo acá deja el estado registrado/swap de preset intacto, solo sin la interrupción. Cada llamada nativa nueva va con su propio log antes/después, misma disciplina de siempre ante un crash.

**Bug 2 (seguimiento real) — el mecanismo real confirmado en el propio header:** `UPalAIActionComponent:SetRootComposite(NuevaAcción, Prioridad)` + `UPalAIActionOtomoDefault:SetOtomoFollowAction()` — la capa de decisión real que usa un Otomo de verdad. Nueva `Combat.attempt_real_otomo_follow()`, llamada desde `Combat.StartFollowing` justo después del `[FOLLOW-DIAG]` de solo lectura ya existente: resuelve la clase nativa vía `StaticFindObject`, construye una instancia nueva propia del `AIActionComponent` del Pal (mismo patrón seguro ya probado en `apply_forced_preset` de `Personality.lua`), llama `SetOtomoFollowAction()`, y después `SetRootComposite()`. **Aditivo, no reemplaza nada:** el empujón periódico de `PalMoveToLocation` (`Trust.lua`'s `tick_followers`) sigue activo en paralelo sin cambios — si esto falla en silencio, el seguimiento no queda peor de lo que ya estaba. `EAIRequestPriority::Type` es un enum real de Unreal (no específico de Palworld, del viejo sistema Pawn Actions/AIModule) — se usó el valor "Logic" (3, por el orden estándar del engine: SoftScript=0/HardScript=1/Reaction=2/Logic=3/Ultimate=4), marcado explícitamente como la única suposición real de este arreglo, sin confirmar contra este build específico.

**Dato real encontrado en el propio log YA desplegado en el juego, antes incluso de copiar los archivos de esta pasada:** `palbonds-live.log` ya tenía una línea real de `[FOLLOW-DIAG]` de una sesión pasada, nunca leída — un Petallia salvaje (`BP_FlowerDoll_C`) confirmado con `AIActionComponent` utilizable, `category=0`, `currentAction=BP_AIActionPairCall_FeedItem_C`. Responde directo la pregunta abierta desde la pasada ochenta y seis (¿un Pal salvaje siquiera tiene este componente?) — sí, al menos para esta especie/clase de controller — buena señal de que el intento de seguimiento real de este pase va a tener oportunidad real de correr, no quedar en no-op silencioso.

Verificado con `luaparse` (los tres archivos, limpio), desplegado en la instalación real del juego y en el espejo de `32-PalBonds/mod/`. **Ninguno de los tres arreglos está confirmado en vivo todavía.**

**Plan de prueba para la próxima sesión:** (1) alimentar a un Pal salvaje con un Kinship Peach y confirmar que la secuencia real de comer/feliz se reproduce completa antes de la captura; (2) lograr que un Pal activamente huyendo o peleando cruce el 20% y ver si deja de hacerlo poco después, revisando las líneas `[INTERRUPT]`; (3) vincularse con un Pal hasta que empiece a seguir (50%) y ver si el seguimiento se nota mejor/distinto que antes, revisando las líneas `[REAL-FOLLOW]` — si `SetRootComposite` da `ok` pero nada cambia visiblemente, eso ya sería evidencia real de que la prioridad "Logic" está mal elegida, no de que el enfoque entero falló.

## Continuación 167 (2026-09-06): prueba real de los 3 arreglos de la Continuación 166 — dos bugs reales encontrados y corregidos desde el log, uno confirmado a nivel de mecanismo

Dragón hizo la prueba pedida y pegó el log real completo, más cuatro preguntas directas. Se leyó el log línea por línea en vez de solo confiar en su resumen.

**Interrumpir la acción en curso — seguía sin funcionar, causa real encontrada.** Para el Pal específico que se estaba vinculando (`BP_FlowerDoll_C`), el trigger de 20% ("WON-OVER") disparó bien, pero la línea siguiente fue "has no readable AISensorComponent — cannot swap its real AI" — o sea que `interrupt_and_resense` (el arreglo nuevo de la pasada anterior) nunca llegó a ejecutarse, porque el swap de preset del que depende nunca se aplicó. Confirma que el diagnóstico original de la Continuación 165 ("capa 1": `MaybeBecomeFriendlyByBar` sigue usando la búsqueda de sensor de un solo intento, sin reintento) seguía siendo el bloqueo real — la pregunta de Dragón sobre interrumpir la acción era válida, pero nunca tuvo oportunidad de probarse.

**Arreglo real:** el hook reactivo que ya escucha las decisiones reales de IA del juego (`SelectResponseBySenses`) ve un sensor válido para prácticamente cualquier Pal salvaje cerca, todo el tiempo. Ahora guarda ese sensor en una caché por Pal, para CUALQUIER tier (antes solo lo hacía para tiers distintos de "normal"). `MaybeBecomeFriendlyByBar` y `ForceTier` revisan esa caché primero, antes de caer al escaneo viejo.

**Captura instantánea, arreglada en la dirección correcta esta vez.** El log mostró que en las 3 capturas reales de la sesión, `GetCurrentAction_BP()` nunca se volvió nil — un Pal salvaje siempre tiene alguna acción de IA base (deambular/pastar) ocupando el componente, así que esperar "nil" simplemente quemaba siempre los 20 segundos completos del tope de seguridad (dejando que una Petallia se alejara 267870 unidades del jugador antes de capturar — justo lo que Dragón reportó). Arreglado: ahora se espera a que la IDENTIDAD de la acción cambie respecto a la que estaba corriendo al empezar a esperar (comparando `GetFullName()`), no a que llegue a nil — la acción real de Feed (`BP_AIActionPairCall_FeedItem_C`, un objeto real con su propia identidad) terminando cuenta como "lista", sin importar a qué pase la IA después.

**Seguimiento real — confirmado enganchando correctamente las 3 veces** que el trigger de 50% disparó en la sesión: `StaticConstructObject(UPalAIActionOtomoDefault) ok` → `SetOtomoFollowAction() ok` → `SetRootComposite(priority=Logic) ok`, corriendo en paralelo con el empujón viejo de `PalMoveToLocation`, tal como se diseñó. Respondiendo directo la pregunta de Dragón: SÍ es un mecanismo nuevo y real, no el viejo empujón — pero si de verdad se ve/siente mejor, y si hay asistencia real en combate, sigue sin confirmarse (la clase de composite también expone `SetOtomoCombatAction()` como un modo separado, que este proyecto todavía no llama).

**La idea de Dragón de reusar el mismo mecanismo para el interrupt** (ya que `SetRootComposite` funciona de verdad) es un buen instinto, pero el único modo ya probado (`SetOtomoFollowAction`) haría que cualquier Pal que se vuelva "friendly" empiece a caminar hacia el jugador de inmediato, incluso a un 20% de su barra — mezclando dos umbrales que se diseñaron separados (20% para personalidad, 50% para seguimiento real). No implementado esta pasada — queda como idea real para cuando se confirme un modo de composite más neutral, o se decida que ese efecto secundario es aceptable.

Verificado con `luaparse` (Trust.lua, Personality.lua), desplegado en la instalación real del juego y en el espejo de `32-PalBonds/mod/`. **Aparte:** Dragón preguntó si el "espejo" del que hablo seguía existiendo — sí, es el único que queda (`32-PalBonds/mod/`, plano) desde que la Continuación 95 consolidó y borró el segundo espejo anidado (`palbonds-mod/`) que nunca fue pedido por él — no se dejó de espejar en ningún momento, solo se eliminó la duplicación confusa. También se encontró y se detuvo una tarea de fondo esta sesión (una búsqueda de archivo por todo el disco, ya innecesaria porque el archivo real ya se había encontrado por otra vía) que había quedado corriendo sin que aportara nada.

**Ninguno de los 3 puntos originales está confirmado como completamente resuelto todavía** — los puntos 2 y 4 tienen arreglos nuevos y más certeros; el punto 3 está confirmado enganchando su mecanismo nuevo, pero su mejora real de comportamiento sigue sin confirmar.

## Continuación 168 (2026-09-06): leído el log real directo del juego — dos bugs reales más encontrados y corregidos, un nerf pedido aplicado

Dragón hizo una pregunta de diseño directa sobre el retraso de captura, corrió otra prueba real, y pidió que revisara el log yo mismo en vez de pegarlo — así que se leyó `palbonds-live.log` directo desde la instalación del juego.

**Su pregunta ("¿no corta la reacción Happy del Pal si capturás justo cuando cambia la acción de IA?") resultó ser exactamente correcta, y peor de lo que sonaba.** El log de esta sesión (5 capturas reales) mostró tres fallas reales y distintas del arreglo anterior: una capturó sin poder confirmar que Happy (que corre en un componente completamente distinto, nunca chequeado por esta señal) ya había terminado; otra capturó A MITAD DE UN COMBATE de verdad — la "acción distinta" detectada resultó ser solo una sub-acción del MISMO combate en curso (`BP_AIAction_CombatPal_C` → una sub-acción hija de ese mismo objeto); y una tercera nunca vio ningún cambio en los 20 segundos completos, la misma falla que el arreglo pasado ya debía haber resuelto. Se abandonó por completo la idea de detectar la señal real — ya se intentó de tres formas distintas (`ActionIsEmpty`, nil-check, cambio de identidad) y las tres fallaron en vivo. Ahora es un retraso fijo de 4 segundos después de la interacción que cruza el umbral de captura — el mismo patrón ya aceptado para el seguimiento de Happy después de Play (pasada ciento cuarenta y tres), honrando el propio orden que pidió Dragón desde el principio: "esperar la animación real, y si no se puede, un retraso fijo."

**El arreglo de interrumpir la acción en curso (Continuación 167) SÍ funcionó a nivel de mecanismo esta vez — 5 de 5 intentos reales, sin ninguna falla de "sensor no legible".** Pero Dragón sigue sin ver ningún cambio real de comportamiento — los Pals seguían huyendo/atacando igual después de volverse "friendly". Como las tres llamadas (swap de preset + las dos del interrupt) reportan éxito sin error de Lua, el problema real ahora es más profundo: probablemente hay un estado aparte del preset (quizás un "objetivo ya trabado" que `SelectResponseBySenses` mantiene entre llamadas, o el viejo sistema de Hate/TargetPlayers descartado hace meses como "no es esto") que sigue manteniendo al Pal en su comportamiento viejo, independiente del preset. No se investigó más a fondo esta pasada — es una pregunta de investigación genuinamente nueva.

**Sobre el seguimiento:** confirmado enganchando 5 de 5 veces de nuevo, pero las 5 veces el Pal terminó capturado en la misma sesión (algunos en minutos, uno en apenas segundos). Esto explica de una sola vez las dos quejas de Dragón: la Petallia que cruzó 50% y "no siguió para nada" (el trigger sí disparó y el mecanismo sí se enganchó las 5 veces — lo más probable es que la captura llegó tan rápido después que nunca hubo tiempo real de verla moverse), y los Pals que sí siguieron pero "no ayudaron a pelear" (misma causa — nunca hubo una ventana de tiempo real para que una pelea pasara entre el inicio del seguimiento y la captura).

**Nerf pedido por Dragón, aplicado:** la ganancia pasiva de confianza (mientras un Pal sigue) bajó de 5 a 2 por tick — apunta directo al problema de la ventana demasiado corta identificado arriba.

Verificado con `luaparse` (Trust.lua), desplegado en la instalación real del juego y en el espejo de `32-PalBonds/mod/`.

**Sigue sin confirmarse:** si el efecto real de comportamiento del interrupt es alcanzable sin investigar más a fondo qué otro estado mantiene a un Pal en su vieja conducta; si el nuevo retraso fijo de captura (4s) alcanza en la práctica para que Happy se vea completo; y si el seguimiento/asistencia en combate se ven bien ahora que el nerf de ganancia pasiva debería dar más tiempo real de observación.

## Continuación 169 (2026-09-06): Dragón hizo una prueba controlada que descarta la teoría de "sin ventana de tiempo" — un valor de retorno real nunca revisado, el composite nuevo retirado, una función de reset real probada para el interrupt

Dragón corrigió directo mi teoría de la pasada anterior: hizo una prueba controlada a propósito, dejando de interactuar apenas una Petallia cruzó 50%, y la observó desde lejos — nunca siguió. Con una segunda, corrió lejos a propósito — terminó despareciendo (despawn), o sea que nunca avanzó nada intentando alcanzarlo. Dos resultados negativos reales y controlados, no un artefacto de tiempo.

**Hallazgo real y concreto: `Combat.IssueFollowMoveOrder` nunca revisó el valor de retorno de `PalMoveToLocation`, en ninguna pasada desde el primer intento de seguimiento de este proyecto.** El header confirma que la función SÍ devuelve algo real: `TEnumAsByte<EPathFollowingRequestResult::Type>` (el enum estándar de Unreal: 0=Failed, 1=AlreadyAtGoal, 2=RequestSuccessful). Si esta llamada viene devolviendo "Failed" en silencio todo este tiempo, eso solo explicaría los dos reportes de Dragón sin necesitar ningún misterio más profundo de estado de IA. Arreglado: el valor de retorno ahora se captura y loguea en cada llamada (`[MOVE-ORDER-RESULT]`) — una lectura simple de un byte, sin riesgo nuevo, pero la primera vez que este proyecto realmente mira si esta llamada tiene éxito.

**El intento nuevo de `SetRootComposite`/`UPalAIActionOtomoDefault` (Continuación 167) se retiró para la próxima prueba** (comentado, no borrado). Se había desplegado bajo la idea de que corría "puramente en paralelo" sin interferir con las llamadas directas de `PalMoveToLocation` — pero el propósito entero de `SetRootComposite` es REEMPLAZAR el comportamiento raíz del AIController, un riesgo real de que esté bloqueando/ignorando en silencio esas mismas llamadas directas hechas sobre el mismo controller, en vez de coexistir con ellas como se pensó. Con dos mecanismos sin confirmar corriendo juntos y cero seguimiento visible en una prueba controlada, no hay forma de saber cuál (o si los dos) está fallando. Se aisló el mecanismo viejo, ahora instrumentado, para una prueba limpia.

**Interrupt — Dragón preguntó directo: "¿no pueden simplemente resetear su comportamiento para que dejen de pelear/huir?"** Llevó a una función real y concreta, ya en el mismo sensor que este proyecto ya lee con seguridad: `ResetResponsedMaxBiologicalGrade()`, junto a su propio campo `ResponsedMaxBiologicalGrade` (un int32 plano). El nombre y la forma sugieren fuertemente un valor de histéresis — "el grado de amenaza más fuerte al que ya reaccioné" — pensado para evitar que un Pal reaccione de nuevo a algo más débil que una decisión que ya tomó. Esto explicaría perfecto por qué el combo de swap+cancel+resense de la pasada anterior tuvo éxito real 5 de 5 veces sin ningún cambio de comportamiento visible: el preset cambió, pero este otro valor separado nunca lo hizo, así que la próxima decisión real del juego pudo haberse descartado en silencio antes de siquiera consultar el preset nuevo. Agregada justo al lado de las otras dos llamadas ya existentes en `interrupt_and_resense`, calzando casi literal con las propias palabras de Dragón.

**Retraso de captura, subido de 4 a 5 segundos**, a pedido explícito de Dragón, para seguir ajustando desde ahí.

Verificado con `luaparse` (Trust.lua, Personality.lua, Combat.lua), desplegado en la instalación real del juego y en el espejo de `32-PalBonds/mod/`.

**Plan de prueba para la próxima sesión:** (1) vincular un Pal hasta 50% sin sobre-alimentarlo, observar desde lejos, y revisar el log por `[MOVE-ORDER-RESULT]` — si reporta 0 (Failed) siempre, esa sería la causa raíz real y de larga data por fin encontrada; (2) llevar un Pal huyendo/atacando más allá del 20% de personalidad y observar de cerca si esta vez sí cambia algo real, revisando que `ResetResponsedMaxBiologicalGrade` reporte éxito; (3) confirmar si el retraso de captura de 5 segundos se siente bien, o avisar cuánto más ajustar.

## Continuación 170 (2026-09-06): balance aplicado, una autocorrección real sobre Pet, y un plan acordado con Dragón antes de tocar el follow/interrupt/combat-assist

Cambios de balance implementados y desplegados: Feed 60→50, ganancia de Play 10→25, tecla de Play movida de CTRL+J (Dragón la encontraba muy incómoda de usar, dos teclas) a F8 sola — confirmado con Dragón que F9/F10 (Pet/Feed) se quedan igual, ya que él usa el menú radial real para eso, que internamente llama a las mismas funciones.

**Autocorrección real, encontrada al implementar el pedido de subir Pet a 25.** Mi afirmación de la sesión anterior ("Pet solo da 10") estaba mal. El hook `[WATCH]` sobre `AddFriendShip` es GLOBAL e incondicional — loguea cualquier regalo real de amistad en todo el juego, no solo los de este mod. Los `value=10 applyPassiveSkill=true` que veníamos leyendo como si fueran de Pet eran casi seguro la ganancia pasiva ambiental de los propios Otomos reales de Dragón (el valor real de vanilla `FriendshipPoint_AutoIncrementOtomo` es exactamente 10). Nunca hubo una lectura limpia y aislada del regalo real de Pet para un Pal salvaje específico. En vez de adivinar de nuevo, `do_interaction` ahora mide el FriendshipPoint antes y ~3 segundos después de un Pet real (solo para Pals salvajes confirmados) y ajusta — positivo o negativo — para que el total quede exactamente en 25, sea cual sea el número real de vanilla. Esto también da, por primera vez, una lectura limpia de ese número real.

**El hallazgo de comportamiento más útil de todo este proyecto hasta ahora:** Dragón observó a una FlowerRabbit mirar hacia él por un instante (la orden de movimiento llegando) y volver a su propio camino un frame después, repitiéndose cada ~1.5 segundos. Confirma visualmente, por primera vez, la debilidad ya documentada del empujón viejo: compite con la IA propia del Pal en vez de reemplazarla.

**Aclaración real importante:** el mecanismo nuevo (`SetRootComposite`) NO estaba activo durante esa observación — se había desactivado la pasada anterior a propósito para aislar el mecanismo viejo. Dragón pensaba que estaba probando el nuevo y se confundió con razón. Teoría real de por qué el nuevo probablemente comparte el mismo problema: solo se llamó UNA vez, al empezar a seguir, nunca de forma repetida — si la IA salvaje reafirma su propia decisión de forma continua, un solo empujón se perdería casi al instante, produciendo un resultado indistinguible de lo que se acaba de observar.

**Plan acordado, NADA de esto implementado todavía (pedido explícito de Dragón):**
1. Reactivar `SetRootComposite`, pero llamarlo REPETIDAMENTE (misma cadencia ~1.5s que el empujón viejo), no una sola vez.
2. Desactivar el empujón viejo de `PalMoveToLocation` para esta próxima prueba, para aislar limpiamente si los empujones repetidos del composite alcanzan para ganarle a la IA salvaje — preferencia explícita de Dragón ("ideally we won't need [the old one]").
3. Para el combat-assist (nunca implementado en ningún mecanismo — solo se llamó `SetOtomoFollowAction()`, nunca `SetOtomoCombatAction()`): antes de escribir un disparador a ciegas, releer la lógica real de `PalFunnelCharacter`/`BP_AIAction_FunnelFollow_C` del mod de referencia PalFollowerTweaks específicamente para esta pregunta (nunca revisada con este enfoque antes — Dragón tenía razón: aunque nadie hizo esto exacto, los mods pueden tener funciones/hooks reusables), y grepear `Pal.hpp` por qué código nativo llama a `SetOtomoCombatAction()`/`SetOtomoBerserker()` en un Otomo real.
4. Interrupt: Dragón preguntó directo si arreglar el follow arreglaría el interrupt también. Respuesta: probablemente relacionado (misma forma "un solo intento vs. IA que se reafirma sola"), pero con una causa real y DISTINTA que no se puede descartar: los campos `Damaged_Player/Greater/Equal/Smaller` del preset "friendly" que se copia nunca se verificaron (solo se asumió que son pacíficos igual que los campos `Discover_*`) — si un Pal ya está enganchado en combate, su decisión puede depender de esos campos en vez de los de descubrimiento. Plan: agregar un diagnóstico que loguee los 8 valores reales copiados antes de asumir que "repetir la llamada" alcanza para arreglarlo.
5. Confirmado por lectura de código, sin probar en vivo todavía: nada en `BondingState`/`State`/`tick_followers` limita el seguimiento a un solo Pal — varios deberían poder seguir en paralelo hoy mismo, sin necesitar ningún cambio.

Verificado con `luaparse`, desplegado en la instalación real del juego y en el espejo de `32-PalBonds/mod/`.

## Continuación 173 (2026-09-06): seguimiento confirmado NO funciona vía composite, Daedream/Dazzi/Floppie investigado (ya estaba resuelto en la 137), un bug real de diagnóstico post-captura arreglado, lag diagnosticado

Dragón probó el composite repetido en vivo (empujón viejo apagado) — resultado negativo y limpio en las 3 veces que un Pal cruzó 50%: `SetRootComposite ok` siempre, pero cada Pal rompió la correa sin moverse hacia el jugador ni una vez. Revertido a ambos mecanismos apagados (no reactivado el empujón viejo, a pedido de Dragón — buscar algo mejor primero). Investigación de Daedream/Dazzi/Floppie retomada: el mecanismo real (`PalFunnelCharacter`/`BP_AIAction_FunnelFollow_C`) comparte el mismo `SetOtomoFollowAction()` ya confirmado que no funciona, y depende de propiedad real (`GetTrainer()`) igual que Otomo completo — ninguno de los dos es una alternativa real para un Pal todavía salvaje. Bug real encontrado y arreglado en `diagnose_post_capture_slot` (Capture.lua): resolvía el handle del Pal DESPUÉS de la captura, cuando el actor ya estaba siendo desarmado — movido a ANTES. Arreglado también un bug cosmético en `Combat.Init()` (leía un toggle antes de su declaración real, típico problema de "los locals de Lua no hacen hoisting"). Diagnosticado (sin arreglar) el lag general — candidato: `[OTOMO-GETTER-WATCH]` re-logueando casi cada llamada por comparar direcciones de wrapper crudas en vez de un valor normalizado.

Verificado con `luaparse` (Combat.lua, Interaction.lua, Capture.lua), desplegado. Detalle completo en `hook-points.md` ("Two-hundred-and-fourth pass").

## Continuación 174 (2026-09-06): tres correcciones reales de Dragón sobre la pasada anterior — sesión cerrada, retoma otra IA

Dragón corrigió tres malentendidos de la Continuación 173, todos documentados con su cita textual en `hook-points.md` ("Two-hundred-and-fifth pass"): (1) que un Pal ya capturado siga como Otomo real NUNCA fue una pregunta abierta — estaba confirmado desde muy temprano en el proyecto; el arreglo del bug de `diagnose_post_capture_slot` se queda pero no cierra nada real. (2) El pedido del VFX era sobre el momento real de la captura (el Pal se pone feliz y luego desaparece sin nada en el medio, falta el efecto de "convertirse en luz y viajar hacia el jugador") — implementado el lado feliz (`play_join_celebration_then` en Capture.lua, Happy + corazones antes de capturar, confirmado bueno), pero el VFX de luz en sí sigue sin encontrarse (el candidato `ABP_ReturnPalEffect_C` ya estaba descartado desde la Continuación 163, así que sugerir "cambiá de Otomo para verlo" respondía la pregunta equivocada). (3) El lag sigue sintiéndose peor que el día anterior — el arreglo de `OTOMO-GETTER-WATCH` no lo cerró, sigue sin causa real encontrada. Se encontró y mató de paso un proceso `find.exe` colgado desde una sesión anterior (sin relación con el lag del juego).

**Dragón pidió explícitamente cerrar la sesión acá y retomar con otra IA distinta**, citando fallas repetidas de entendimiento. Ver el banner "🔴 SESIÓN CERRADA" al principio de este archivo y el detalle completo (con las citas textuales) en `hook-points.md` ("Two-hundred-and-fifth pass") antes de tocar cualquier cosa.

## Continuación 175 (2026-09-06): sesión nueva (otra IA) — auditoría inicial, un error propio corregido, y seis fuentes reales de lag encontradas y eliminadas

Sesión retomada por un asistente distinto, según el pedido explícito de la Continuación 174. Se leyó el archivo completo, la lista "EMPEZAR ACÁ", `DESIGN.md` §12 y la "Two-hundred-and-fifth pass" de `hook-points.md` antes de tocar nada.

**Error propio, corregido de inmediato:** la auditoría inicial reportó los Kinship Peaches como "bloqueados, sin implementar". Es falso — están implementados, balanceados y probados en vivo (`Interaction.lua`, post-hook de `RequestUseToCharacter`: 250 puntos para `AffectionFruit_02`, 500 para `AffectionFruit_01`, contra una barra de 500). El error vino de leer el estado desde `DESIGN.md` §12 (un documento de planificación del 2026-09-03) en vez de revisar el código. Dragón lo corrigió con una observación importante: el problema no es la línea equivocada en sí, sino que una línea equivocada indica que no se está viendo el trabajo más reciente completo. `DESIGN.md` §12 quedó marcado como SUPERSEDED con las cuatro correcciones concretas escritas encima, para que no vuelva a engañar a nadie.

**Lag — seis causas reales encontradas y eliminadas.** Por primera vez se analizó el log real por frecuencia de etiqueta (2012 líneas en 10 minutos) en vez de suponer. Ninguna de estas se había identificado antes:

1. **`Indicator.lua` — hook sobre `PalUICharacterHPGaugeBase:SetHPPercent`.** La peor de todas. El juego llama esta función continuamente para CADA barra de vida visible en pantalla. Cada llamada cruzaba a Lua y ejecutaba `describe_widget()` (una llamada real de reflexión `GetFullName()`) más un `string.format` **antes** de que el tope de logs pudiera descartar el resultado — porque Lua evalúa los argumentos antes de llamar a la función. O sea: el tope silenciaba la SALIDA, pero el trabajo real seguía ocurriendo en cada llamada, toda la sesión. Costo invisible en el log (solo aparecen 20 líneas) que escala directo con cuántos Pals hay en pantalla — exactamente la forma del lag "peor al entrar a zonas nuevas". **Eliminado.** El hook hermano `SetTargetCharacter` tenía la misma forma con dos reflexiones por llamada. **Eliminado.**
2. **`OtomoWatch.lua` completo — 11 hooks, desactivado.** Nada del mod llama a este módulo (solo exporta `Init()`), todas sus preguntas están cerradas, y dos de sus hooks están sobre funciones calientes de verdad: `SelectResponseBySenses` (cada decisión de sentido de cada Pal — **y además duplicaba el hook que `Personality.lua` ya tiene ahí para el enforcement real**) y `TargetIsPlayerOrPlayersOtomoPal` (cada evaluación de objetivo en combate), ambos logueando incondicionalmente con reflexión. Más un poll de `FindAllOf` cada 10s cuyo propio comentario admite que no tiene uso planeado. **`OtomoWatch.Init()` comentado en `main.lua`.**
3. **`Personality.lua` — `interrupt_and_resense` en el camino equivocado.** Disparaba sobre 43 Pals distintos en 10 minutos, porque estaba enganchado al enforcement de rutina (el que le pone su preset a cada Pal salvaje al aparecer) en vez de solo a los dos caminos que lo necesitan de verdad (`MaybeBecomeFriendlyByBar` y `ForceTier`). Un Pal recién visto no tiene ningún comportamiento viejo que interrumpir — se le estaba cancelando la acción y forzando un `RequestSightCheckAsync` (un trazo de visión asíncrono) sin motivo. **Detalle de tiempo que encaja con el reporte de Dragón:** las dos llamadas se agregaron el 2026-09-06 (Continuaciones 167 y 169), justo cuando él dijo "lag still feels a lot laggier than yesterday, im sure it was something last added". **Sacado de ese camino; el swap de preset queda intacto.**
4. **`Indicator.lua` — `poll_prism_state` cada 2 segundos.** Dos escaneos `FindAllOf` de todo el mundo (`BP_CapturePrism_C` y `BP_CapturePrismBullet_C`) más una reflexión por instancia, para siempre. Sus throttles solo frenaban las líneas de log, nunca los escaneos. La investigación que alimentaba está cerrada. **Sacado del tick.**
5. **`Interaction.lua` — hook `[WATCH]` global sobre `AddFriendShip`.** Logueaba con reflexión cada regalo de amistad de todo el juego, incluida la ganancia pasiva ambiental de cada Otomo y cada trabajador de base — un flujo constante en una partida real. Además era engañoso: fue justo el que produjo la conclusión equivocada corregida en la Continuación 170. **Eliminado** (la medición real y dirigida en `do_interaction` ya lo reemplaza).
6. **`Interaction.lua` — camino ocioso de `TryGetSpawnedOtomo`.** Este hook **no se puede sacar** (es la sustitución que hace que Pet funcione sobre un Pal salvaje), pero el getter dispara ~4 veces por segundo y hacía `hook_get` + `hook_describe` (reflexión) en cada llamada antes de cualquier throttle. El arreglo de la Continuación 204 corrigió las líneas repetidas pero dejó la reflexión, que siempre fue el costo mayor. **Ahora el camino ocioso es un solo test booleano y un return.**

**Aparte, misma pasada:** `Trust.lua` logueaba `[TICK]` incondicionalmente cada 1.5s (396 líneas en 10 minutos) con un logger que fuerza escritura a disco por línea — ahora se loguea una sola vez. Y `try_enforce_personality` ahora consulta primero la caché de sensores del hook reactivo antes de caer al escaneo proactivo, que reconstruía un índice de TODO el mundo (`FindAllOf("PalAISensorComponent")` + dos reflexiones por componente) cada 5 segundos.

Los 11 archivos verificados con `luaparse`, desplegados en la instalación real y en el espejo de `32-PalBonds/mod/`.

**Prueba pendiente, y es la que importa:** jugar normal, sobre todo entrando a zonas nuevas con muchos Pals, y decir si el lag mejoró. Ninguno de estos seis arreglos está confirmado en vivo todavía — están confirmados como costos reales por lectura de código y del log, que no es lo mismo. **Confirmar también que nada se rompió**, ya que se tocaron caminos vivos: que Pet/Feed/Play sigan funcionando, que la barra de confianza y la etiqueta de personalidad sigan apareciendo, y que los Pals salvajes sigan mostrando comportamientos variados según su tier.

## Continuación 176 (2026-09-06): causa raíz de las ganancias irregulares de amistad — encontrada y arreglada; F9/F10 eliminados; enfoque nuevo para seguimiento y ayuda en combate

**MODO DE VERIFICACIÓN DE BALANCE ACTIVO AHORA MISMO.** Pet/Feed/Play = 100 cada uno, multiplicador de nivel forzado a 1.0, ganancia pasiva en 0. Diseño de prueba del propio Dragón: 5 interacciones de cualquier tipo deben capturar a cualquier Pal (5 × 100 = umbral 500). Para volver a los valores reales hay que apagar DOS banderas: `BALANCE_VERIFICATION_MODE` (Interaction.lua) y `LEVEL_MULTIPLIER_DISABLED_FOR_BALANCE_TEST` (Trust.lua). Valores reales guardados en los comentarios de ambas: Pet 25, Feed 50, Play 25, pasiva 2. Los Kinship Peach NO se tocaron a propósito (ya confirmados correctos, 250/500).

**Causa raíz real de la irregularidad — no era un problema de números.** En un Pet por menú radial sobre un Pal salvaje sustituido, `closeRadialMenuActionWindow` llamaba a `do_pet()`, que entra en `do_interaction()`. La PRIMERA compuerta de esa función es "¿el jugador ya está a mitad de una acción? entonces ignorar" — un anti-spam pensado para una tecla. En el camino radial esa compuerta está directamente equivocada: el sentido entero de la sustitución es que la acción real de Cuidar del juego arranca en ese mismo instante, así que el jugador SÍ está a mitad de una acción, la compuerta dispara, y `do_interaction` regresa antes de llegar al otorgamiento de amistad Y antes de llamar a `Interaction.OnWildPalPetted(pal)`.

Esa llamada es la que habilita TODO lo demás en Trust.lua: el trigger de 20% (friendly), el de 50% (seguir), el chequeo de captura, y hasta si el Pal recibe barra de confianza. Así que un Pet radial registraba todo o nada según si nuestra llamada le ganaba la carrera a la animación de vanilla. Eso explica exactamente lo que Dragón viene reportando: ganancias irregulares, barras que aparecen tarde, y varios umbrales disparando de golpe cuando por fin pasa un Feed.

**Arreglo:** `grant_wild_interaction(pal, monto, etiqueta)` — la mitad de contabilidad de `do_interaction`, extraída sin compuertas de ocupado y sin `PlayActionByType`: guarda de propiedad, lee antes, `AddFriendShip`, loguea `[BALANCE-TEST]` con antes/después/intención, y llama a `OnWildPalPetted`. El camino radial ahora usa esto en vez de `do_pet()` (vanilla ya está reproduciendo la animación; nunca se quiso una segunda).

**Segundo bug real: Play siempre otorgó CERO.** Dependía de que la acción Happy diera amistad como efecto secundario — algo que la Continuación 132 ya había refutado con una prueba controlada. El `AddFriendShip` explícito solo existía en una rama de respaldo que corre si falla el AGENDADO, o sea prácticamente nunca. El rebalanceo de 10→25 que pidió Dragón se aplicó a una constante que nunca se ejecutaba. Ahora otorga de verdad.

**F9/F10 eliminados**, a pedido explícito de Dragón. Regla de diseño que queda fijada y NO hay que volver a discutir: **Pet y Feed son interacciones del menú radial, no teclas.** Play conserva F8 solo porque todavía no tiene equivalente en el menú radial — y según Dragón, debería mudarse ahí también cuando se pueda. Esto además elimina una fuente real de confusión en el propio diagnóstico de este proyecto: varias pasadas razonaron sobre "lo que da F9" como si fuera lo que Dragón veía en el juego, cuando él nunca la presionó.

**Seguimiento — enfoque nuevo de verdad, no otro reintento.** Hallazgo decisivo: el vocabulario completo de decisiones de la IA es `EPalAIResponseType: Ignore=0, Escape=1, Battle=2, Special=3`. **No existe un valor "acercarse/seguir"** — por eso la capa de presets, por sí sola, jamás puede producir seguimiento. Pero sí puede CALLARLA: poniendo en `Ignore` las respuestas del Pal hacia el jugador, su IA deja de generar decisiones sobre él, y entonces no queda nada que pise la orden de movimiento. `Personality.ApplyCompanionPreset` hace eso, reusando la escritura de preset privado ya probada. Junto con dos cambios en Combat.lua: el empujón de movimiento vuelve a estar ENCENDIDO, y ahora cada orden va precedida por `AllCancelAction_Logic_HardScript_Reaction` — el mismo interrupt confirmado 5/5 en Pals salvajes, nunca antes combinado con movimiento.

**Ayuda en combate**, con el visto bueno de Dragón, viaja en el mismo preset: las tres ranuras `Discover_*` que no son del jugador pasan a `Battle`, mientras las del jugador quedan en `Ignore` — un compañero que pelea contra otros Pals y nunca contra el jugador. Limitación honesta: pelea contra lo que detecta, no específicamente contra lo que el jugador está peleando.

Los 11 archivos verificados con `luaparse`, desplegados y verificados por md5. **Nada de esto está confirmado en vivo.** Detalle completo en `hook-points.md` ("Two-hundred-and-seventh pass").

## Continuación 177 (2026-09-06): números de balance VERIFICADOS en vivo, el peor tirón de rendimiento del proyecto arreglado, y la ayuda en combate corregida desde tres reportes de Dragón

**Verificación de balance: PASÓ.** Las 25 ganancias registradas en la corrida de Dragón dan exactamente +100, sin una sola excepción — Pet por menú radial y Feed real por `RequestUseToCharacter`. Seguir dispara en la interacción 3 y la captura en la 5, tal como se diseñó.

**Hallazgo nuevo dentro de esos mismos datos: el otorgamiento propio de vanilla al acariciar un Pal SALVAJE es +10.** Se ve en los valores "antes": tras un Pet que deja 100, la siguiente interacción arranca en 110; 210 → 220; 320 → 330; 430 → 440. La deriva es siempre exactamente 10, siempre viene después de un **Pet**, y nunca después de un Feed. Nuestro otorgamiento es inmediato al cerrar el menú; el de vanilla llega un momento después, cuando termina su animación de Cuidar. Esto corrige un supuesto viejo: el valor real es **10, no los 30** que reporta `UPalGameSetting.Petting`. **Consecuencia para el balance real: un Pet radial vale NUESTRO monto + 10.** Para que quede en los 25 que quiere Dragón, `PET_FRIENDSHIP_GAIN` debe ser 15, no 25. Anotado, no cambiado todavía, porque el modo de verificación sigue encendido.

**Respuesta directa a la pregunta de Dragón ("¿son las cosas nuevas, o los 3 seguidores?"): las dos, y se pueden separar.** `[MOVE-ORDER-RESULT]` escribía 2-3 líneas cada 1.5s POR seguidor, cada una forzada a disco — eso escalaba exactamente con la cantidad de seguidores. Aparte, y más grave: `[RADIAL-REDIRECT-PERF]` (el diagnóstico agregado la pasada anterior) demostró que `find_targeted_pal` cuesta **48-74ms por escaneo**, y se recalcula 4 veces por segundo mientras el menú radial está abierto — unos 200-300ms de Lua bloqueando frames por cada segundo de menú. Ese es el peor tirón del proyecto y no tiene relación con los seguidores, pero se dispara con cada tecla "4". Causa dentro de la función: llamaba `GetFullName()` (una llamada de reflexión que construye un string) sobre CADA Pal del mundo cargado, solo para excluir a un actor. Arreglado: primero la geometría barata, y la exclusión se resuelve solo sobre el único candidato ganador.

También recortados: el rastreo `[RADIAL-WATCH]` (~8 líneas por cada "4", cuatro reflexiones cada una — más de la mitad del log que pegó Dragón; ahora detrás de `VERBOSE_MENU_HOOK_TRACE`, apagado) y `[RADIAL-REDIRECT-FIELD]` (8-10 líneas por tecla, ahora una por ventana de menú).

**La buena noticia de la corrida, confirmada por log:** `PalMoveToLocation` devolvió solo 2 (éxito) y 1 (ya está en el destino) en toda la sesión, **nunca 0 (fallo)**. Que domine "ya está en el destino" significa que los seguidores de verdad llegaban y se quedaban con el jugador. El enfoque del preset de compañero funcionó — el problema de seguimiento, por primera vez, se está comportando.

**Ayuda en combate: tres reportes, una sola causa.** Dragón vio (1) una Petallia vinculada atacando a su Flopie vinculada sin provocación, (2) compañeros empezando peleas con Pals al azar mientras seguían, recibiendo daño y pasando a escape, y (3) tres compañeros que "seguían pero nunca atacaban, ni siquiera cuando recibían daño" de una Caprity hostil. Los reportes 1-2 y el 3 parecen contradictorios pero salen del mismo error: **`Discover_*` gobierna "noté algo" y `Damaged_*` gobierna "algo me lastimó", y solo se habían puesto en Battle las ranuras Discover.** Así que empezaban peleas con cualquier cosa que veían — incluidos entre ellos, porque otro compañero vinculado es apenas otro Pal salvaje a sus ojos — y a la vez se quedaban quietos recibiendo golpes sin responder. Los saltos a escape del punto 2 son la consecuencia: el daño dispara la penalización de Trust, que puede dejar la confianza en cero y forzar el tier escape.

Corregido, y de paso es el mejor diseño: `Discover_*` = Ignore (nunca empezar una pelea — arregla el fuego amigo y la espiral de muerte) y `Damaged_*` = Battle (responder cuando de verdad los atacan — arregla la pasividad). Además ahora se marca `enforcementApplied` al aplicar el preset de compañero, para que el escaneo periódico de personalidad no lo pise después con el tier original — algo que se habría visto exactamente como un compañero volviéndose hostil solo.

Limitación honesta que queda: un compañero se defiende A SÍ MISMO, no al jugador. Se suma a una pelea que empezó el jugador solo cuando el enemigo también lo ataca a él. Que ataquen directamente el objetivo del jugador necesita el sistema de Hate, todavía sin explorar para este fin.

Los 11 archivos verificados con `luaparse`, desplegados y verificados por md5. **Nada confirmado en vivo.** Detalle en `hook-points.md` ("Two-hundred-and-eighth pass").

## Continuación 178 (2026-09-06): el arreglo de Dragón para el deambular, ayuda en combate real vía sistema de Hate, aviso de captura con nombre, y una pista nueva de verdad para el VFX

**La causa del deambular la diagnosticó Dragón, no la instrumentación.** Sus palabras: los Pals llegan hasta él, se quedan sin nada que hacer, y ahí su IA normal vuelve a activarse y los manda a un punto lejano; lo confirmó al revés — moviéndose sin parar nunca pasa, porque nunca tienen tiempo ocioso. El log lo respalda: el resultado de la orden de movimiento queda en 1 (ya está en el destino) justo cuando ocurre.

**Su arreglo, implementado tal cual:** si ya está en el destino, en vez de dejarlo ocioso, hacer que reproduzca una animación para que esté ocupado. Cuando la orden devuelve "ya está en el destino" Y el ActionComponent del Pal reporta vacío, se reproduce `ACTION_TYPE_PAL_RANDOM_REST` (77), la misma acción que ya usa Play, o sea probada como segura en un Pal salvaje. **Es mejor que la alternativa que estaba por construirse** (un tick más rápido que cancela y reemite la orden 2 veces por segundo), por una razón concreta: cancelar la acción del Pal dos veces por segundo también cancelaría sus ataques, rompiendo la defensa propia recién arreglada. Ocupar a un Pal ocioso no puede interrumpir nada, porque la compuerta `ActionIsEmpty()` hace que solo corra cuando el Pal no está haciendo absolutamente nada.

**Ayuda en combate, ahora con objetivo real vía el sistema de Hate.** El reporte de Dragón era que los compañeros se defienden pero "siguen sin defenderme". Lo que faltaba nunca fue la disposición (`Damaged_*` = Battle ya funciona) — era que el compañero no tenía ningún motivo para considerar suyo al enemigo del jugador. Confirmado real en el volcado de headers de esta build, no adivinado: `APalAIController::GetHateSystem()`, `UPalHate::ChangeHate(Actor, float)`, `UPalHate::FindMostHateTarget()`. Se maneja desde el hook de `PalHate:DamageEvent` que Trust.lua YA tenía instalado: cuando el jugador da o recibe daño, el otro actor de ese evento es por definición su enemigo actual, así que `Combat.OnPlayerCombatTarget(enemigo)` empuja hate sobre cada compañero que está siguiendo. Sin sondeo, sin escaneo — el juego nos entrega el actor.

**Incertidumbre declarada, a resolver con la próxima prueba y no por suposición:** el hate le da un OBJETIVO al compañero, pero que su IA decida atacarlo puede seguir dependiendo del preset, cuyas ranuras `Discover_*` están a propósito en Ignore para que no empiecen peleas. Si el hate solo no alcanza, el siguiente paso es permitir Battle al descubrir únicamente mientras haya un objetivo activo del jugador, no de forma permanente. Las líneas `[HATE-ASSIST]` lo van a distinguir.

**El aviso de captura ahora nombra al Pal**, según el pedido de Dragón. Para que diga "Petallia" (el nombre que él ve) y no el id interno "FlowerDoll" se usan dos piezas reales del volcado: `UPalMasterDataTablesUtility::GetLocalizedText(...)` con `EPalLocalizeTextCategory::PalMonsterName = 4` y el CharacterID del Pal. Todo protegido con pcall y doble respaldo (nombre localizado -> CharacterID crudo -> el texto genérico de antes): un aviso cosmético jamás debe romper una captura que ya salió bien.

**VFX DE UNIÓN — candidato nuevo de verdad, el primer avance real desde que se descartó `ABP_ReturnPalEffect_C`.** Encontrado buscando en el volcado de headers, no reciclando una corazonada: `APalCapturedCage::StartCaptureEffect_ServerBP(APalPlayerCharacter* Player)` y, en el Blueprint `ABP_PalCapturedCage_C`, un `UNiagaraComponent* Niagara`. Coincide exactamente con lo que Dragón describe al mirar un rescate de jaula normal, y recibe al JUGADOR como argumento — consistente con un efecto que viaja hacia él. **Hallazgo estructural importante: el efecto pertenece al actor JAULA, no al Pal.** Así que no se puede llamar sin más sobre un Pal salvaje cualquiera; reproducirlo significa leer el *asset* Niagara del componente de la jaula y hacerlo aparecer en la posición del Pal vinculado. Es un próximo paso concreto y real, pero necesita una jaula viva en el mundo para leer el asset, o una lectura de ese Blueprint en FModel para sacar la ruta — no es algo para adivinar. A propósito NO se implementó a ciegas en esta pasada.

Los 11 archivos verificados con `luaparse`, desplegados y verificados por md5. **Nada confirmado en vivo.** Detalle en `hook-points.md` ("Two-hundred-and-ninth pass").

## Continuación 179 (2026-09-06): la animación de descanso revertida (error mío, usé una señal que el proyecto ya sabía que no es confiable), el bug del aviso de captura con causa real, y la sonda del VFX de la jaula que debió salir la pasada anterior

**La animación de descanso se ELIMINÓ. Fue un error mío, y evitable.** La prueba de Dragón mostró que salió mal de tres formas distintas, todas reales: (1) interrumpía su propia interacción de Pet/Feed/Play justo cuando el Pal cruzaba el 50%; (2) una vez descansando, el Pal contaba como ocupado, así que la orden de seguimiento no podía moverlo — quedaban clavados en vez de seguir; (3) ni siquiera cumplió su objetivo: igual se iban a deambular.

La causa de (1) es lo importante: la condicioné a `ActionIsEmpty()`, **una señal que este proyecto ya tenía documentada como poco confiable justo para esto.** La pasada 196 dejó escrito que "se libera casi al instante" — reporta vacío en los huecos entre los pasos de una interacción real de varias partes, que es exactamente por qué disparó a mitad de una interacción. Apoyarme en una señal que las propias notas del proyecto llaman poco confiable no fue una decisión defendible; lo correcto era revisar ese historial antes de construir encima.

**Reemplazo, atacando la misma causa raíz pero por el sistema de MOVIMIENTO en vez del de acciones**, así que estructuralmente no puede interrumpir una animación ni bloquear una pelea:
- Si el Pal tiene un objetivo de odio (`UPalHate::FindMostHateTarget`, el mismo sistema al que empuja la ayuda en combate), la lógica de seguimiento no hace nada — a un compañero peleando se lo deja en paz. Esto además evita que la orden de seguimiento compita con la ayuda en combate agregada la pasada anterior.
- Si no, cuando la orden devuelve "ya está en el destino", se reemite hacia un punto que orbita lentamente alrededor del jugador en vez de su posición exacta. Así el Pal siempre tiene una ruta activa y nunca recibe una ventana ociosa — que es exactamente la condición que Dragón ya confirmó que funciona: moviéndose sin parar, esto nunca pasa. Ahora tienen esa misma condición aunque él esté quieto.

**El bug del aviso de captura, con causa real, y es la misma clase de bug que este proyecto ya arregló una vez.** El código nuevo SÍ corrió (la línea `[NOTIFY] join message:` es nueva de esta pasada) pero cayó al texto genérico, o sea que fallaron las DOS rutas del nombre. La causa es el orden, no la búsqueda del nombre: `NotifyJoined` corre DESPUÉS de `TryDirectCapture`, y el mismo log muestra `owner AFTER the call = nil`. El actor está siendo desarmado, así que su cadena de componentes ya no resuelve y toda ruta falla en el primer paso. **Es exactamente el bug que la pasada 204 arregló en `diagnose_post_capture_slot` — la misma lección, perdida por segunda vez.** Arreglado resolviendo el nombre antes, junto a `preCaptureHandle`, y pasándolo como string que sobrevive a la captura. Regla que conviene recordar: **todo lo que necesite leer del Pal debe leerse ANTES de que corra `PalCaptureSuccess`.**

**Sonda `[CAGE-VFX]` agregada — solo lectura — y su ausencia la pasada anterior fue omisión mía.** Le dije a Dragón que encontrar una jaula desbloquearía el VFX; él fue a un asentamiento enemigo y rescató un Pal ("swee") justamente para eso, pero no existía ningún diagnóstico para leer nada de ahí, así que ese viaje no produjo datos. Ahora corre al iniciar, con reintento acotado, y prueba dos rutas para el asset Niagara de `ABP_PalCapturedCage_C`: instancias vivas, y el objeto por defecto de la clase (que sirve aunque no haya jaula cerca, mientras la clase se haya cargado alguna vez — el rescate de Dragón hizo eso). Solo resuelve objetos y lee campos; nunca llama a `StartCaptureEffect_ServerBP`.

**También confirmado de esta corrida:** `[HATE-ASSIST]` disparó cero veces — esperable, porque ningún compañero llegó a seguir el tiempo suficiente para que hubiera una pelea, así que la ayuda en combate sigue sin probar, no descartada. Y `find_targeted_pal` bajó a 42-47ms (era 48-74ms): sacar el GetFullName por Pal ayudó, pero lo que queda sigue siendo el tirón más grande del proyecto.

Los 11 archivos verificados con `luaparse`, desplegados y verificados por md5. **Nada confirmado en vivo.** Detalle en `hook-points.md` ("Two-hundred-and-tenth pass").

## Continuación 180 (2026-09-06): cuatro bugs encontrados en el log (dos míos de la pasada anterior), la regla de daño sacada a pedido de Dragón, y un primitivo de seguimiento hacia un ACTOR que responde su pregunta sobre SetActiveAI

**1. El aviso de captura — el log dio el error exacto, mucho más útil que el síntoma.** Dragón reportó "no salió ningún texto", que sonaba a regresión. El log dijo lo que pasó de verdad: `attempt to concatenate a FString value (local 'palName')`. O sea que la búsqueda del nombre SÍ funciona — `GetLocalizedText` devolvió un FText real y `Conv_TextToString` devolvió un valor real, pero ese valor es un **FString (userdata), no un string de Lua**, y concatenarlo lanza error. El arreglo de la pasada anterior (resolver antes de la captura) era correcto y necesario; este era un segundo bug independiente escondido detrás, y por eso el síntoma cambió de "texto genérico" a "ningún texto". Arreglado con un helper que maneja ambos casos y que a propósito rechaza el `tostring()` tipo "FString: 0x..." en vez de mostrarle una dirección de memoria al jugador.

**2. `[HATE-ASSIST]` disparó CERO veces, y la causa es un bug que introduje yo, no la falta de peleas.** Trust.lua NO tiene un local `Combat` a nivel de archivo — todos los demás lugares usan `pcall(require, "Combat")` dentro de la función. La pasada anterior escribí `Combat.OnPlayerCombatTarget(enemy)` como si el módulo estuviera en alcance, así que indexó un GLOBAL nulo, lanzó error, y `safe_call` se lo tragó siempre. **Y encima le reporté a Dragón una conclusión equivocada** ("ningún compañero siguió lo suficiente para que hubiera pelea") cuando la llamada simplemente nunca corrió. Arreglado. La ayuda en combate sigue sin haberse ejercitado nunca.

**3. La regla de daño se saca para atacantes que no sean el jugador — decisión de Dragón, y el log la respalda exacto.** En su corrida: una FlowerDoll vinculada recibió 21 de daño de un PinkRabbit salvaje, se comió la penalización completa de -150, quedó en cero confianza y fue forzada a tier "escape" — o sea que huyó en vez de pelear. Su razonamiento: que solo pierdan amistad si el jugador mismo las golpea, porque hoy, para entrar en combate, primero tienen que ser golpeadas por algo. Es correcto, y la regla se había vuelto contraproducente: todo el sentido de `Damaged_*` = Battle es que el compañero reciba un golpe y responda, pero la penalización destruía el vínculo justo en ese momento. El daño de terceros ya no cuesta confianza. La traición del jugador queda intacta.

**4. La sonda `[CAGE-VFX]` tenía un bug que se contradecía a sí mismo, y desperdició el viaje de Dragón.** Su log mostró "NiagaraComponent=nil Asset=nil" e inmediatamente después "asset resolved — probe done". Ambas cosas no pueden ser ciertas. La causa: la línea de log usaba `tostring(obj and obj:GetFullName() or "nil")`, que imprime "nil" tanto cuando el objeto es nulo COMO cuando existe pero falla GetFullName — así que la sonda pudo perfectamente haber tenido el asset y solo no poder imprimir su nombre, y aun así se declaró exitosa. Peor: se marcó terminada al arrancar, así que cuando Dragón fue a un segundo asentamiento a propósito para dar una jaula fresca, ya no había nada mirando. Arreglado en tres frentes: presencia y nombre se reportan por separado, el éxito exige un NOMBRE real, y el reintento dura ~30 minutos en vez de 2 — porque una jaula solo existe cuando el jugador llega hasta ella.

**5. Seguimiento — respuesta a su pregunta sobre SetActiveAI, con una función real, no una variación.** Preguntó si existe algo parecido al viejo `SetActiveAI(false)` (que evitaba el deambular pero dejaba a los Pals tan inertes que se quedaban quietos muriendo) pero menos total. Buscando en `APalAIController` apareció algo mejor que un interruptor de supresión: `SimpleMoveToActorWithLineTraceGround(const AActor* GoalActor, ECollisionChannel)`. **Todos los intentos de seguimiento de este proyecto fueron siempre por UBICACIÓN** — el empujón original, el composite de Otomo y la órbita de la pasada anterior: una orden de "caminá hasta este punto" que se completa, y al completarse el Pal se queda sin objetivo y su IA toma el control. Esta recibe un ACTOR como objetivo, lo cual es continuo por naturaleza: el motor sigue dirigiéndose hacia un blanco que se mueve, que es lo que significa seguir. Además encaja mejor con la observación nueva de Dragón (que igual se van, lo que pone en duda que sea el estado ocioso lo que dispara el deambular): si el problema real es que una orden de punto completada no deja ningún objetivo, un blanco que nunca se "alcanza" elimina la clase entera de problema en vez de parchear el síntoma. Se prueba primero, detrás de un toggle, con la orden por ubicación como respaldo automático.

Los 11 archivos verificados con `luaparse`, desplegados y verificados por md5. **Nada confirmado en vivo.** Detalle en `hook-points.md` ("Two-hundred-and-eleventh pass").



---

# Archived from CLAUDE.md on 2026-09-28 — closed investigations

Moved here verbatim, nothing summarised or deleted, for the same reason as the
2026-09-06 split: `CLAUDE.md` had grown past what one read returns, and a session
that reads it partially reports stale items back to Dragón as open work — which
is exactly what happened on 2026-09-28. Both investigations below are FINISHED and
SHIPPED. Read them only for how something was solved.

## Performance investigation 2026-09-15 (microstutters, fixed in v1.1.2)

This was "Known open defects" item 0. Every PresentMon capture, profile runs C to
E, both fix rounds and the measured before/after. The durable rules it produced
live on in `CLAUDE.md`.

0. **Microstutters — FIXED in v1.1.2 (committed to GitHub 2026-09-15; stores
   still serve 1.1.1).** Kept here as the investigation record. Confirmed as
   the mod's doing on 2026-09-15. Reported by Workshop commenter *Goldaer* (2026-09-14, against
   1.1.0): the mod "appears to introduce a lot of microstutters that are
   really noticeable", visible on Steam's performance overlay. Dragón confirms
   he feels it too and had grown used to it.

   **Baseline measurement** (PresentMon, dev install 1.1.1, same spot, standing
   still, no followers, 2 minutes each; captures in `perf-captures/`, analysed
   with `node tools/perf/analyze-presentmon.js`):

   | | PalBonds ON (runA) | PalBonds OFF (runB, UE4SS still loaded) |
   |---|---|---|
   | avg fps | 68.1 | 70.2 |
   | 1% low | **16.2 fps** | 36.1 fps |
   | 0.1% low | **7.9 fps** | 32.2 fps |
   | worst frame | **139 ms** | 41.7 ms |
   | hitch events | 163 (81.6/min) | 87 (43.5/min) |
   | repeating stall series | **8.115s ~119ms (13/15 slots), 2.050s ~48ms (49/58), 3.065s ~48ms (26/39)** | **none** |

   The average barely moves, which is why it is easy to grow used to; the
   lows collapse. Every repeating series disappears with the mod off, and the
   remaining ~87 unpatterned hitches exist in both runs (the game's own). The
   stalls are CPU-side (CPU-busy equals frame time), i.e. game thread. Each
   period equals a mod timer's delay plus its own stall, because the mod's
   timers reschedule after their work: 8.115s = personality scan (8000ms) +
   ~119ms; 2.050s = nameplate sweep (`SCAN_INTERVAL_MS` 2000) + ~48ms; 3.065s =
   every second Trust tick (1500ms). The mapping is by period only — the
   profiler (Next steps #1) is what proves which code each stall is.

   **The 3.065s series is traced in code (Dragón asked why it runs with no
   followers).** `tick_followers` (`Trust.lua`, the 1.5s tick) calls
   `find_player()` on its first lines, BEFORE looping over `State` to see
   whether anything is following. `find_player` caches the player for
   `PLAYER_CACHE_SECONDS = 2.0`; a 2.0s cache on a ~1.53s tick expires on every
   second tick, so a full `FindAllOf("PalPlayerCharacter")` object-array walk
   runs every ~3.07s for the whole session, with or without a single bonded
   Pal. The cache was built for the per-hit damage path (run 37) and does its
   job there; the tick simply pays for it regardless. The same idle-cost shape
   applies to the 2s nameplate sweep and the 8s personality scan, which also
   run whether or not anything needs them.

   **Profiled run C (2026-09-15, 12:46–12:56, profiler ON, dev install).**
   Dragón's timeline, from F3 at 12:47:41: 2 min idle; walking; fast travel +
   mounted; feeding wild Pals via the radial menu; walking until they joined;
   several followers; a fight with followers; closing the game. Summarise
   with `node tools/perf/analyze-profile.js <palbonds-profile.log> --phase
   "HH:MM:SS label" ...`. Key results:
   - **The clock is trustworthy:** os.clock 611.5s vs wall 612s over the
     session. The 2026-09-07 "os.clock is CPU time" note in Combat.lua is
     WRONG for this build; os.clock is wall time at 1ms resolution.
   - **Nearly every stall is a world search** (`FindAllOf` / `FindFirstOf`).
     Hooks and loops are cheap: `SelectResponseBySenses` 0.03ms/call (8718
     calls in 2 min idle = 231ms total), Combat fast loop <1ms/pass,
     `update_trust_bars` 3–20ms, `try_enforce_personality` and per-Pal
     `GetFullName` ~0.
   - **A single search costs ~40ms idle and 55–100ms in play**, growing with
     what is loaded; timer runs containing several reached 246ms.
   - **Frozen time per minute from world searches alone:** idle ~2.9s (~5%),
     fight ~5.6s (~9%), **feeding via the radial menu ~7.9s (~13%)**.
   - **Biggest single offender in active play (Dragón's hunch was right):**
     the radial redirect hook `TryGetSpawnedOtomo` post-callback, 3.2–3.8s per
     minute while feeding / with several followers, driven by
     `FindFirstOf("PalPlayerCharacter")` at `Interaction.lua:2245`, called on
     EVERY hook fire while the 15s radial window is open (~4/s, ~50–60ms each).
     `WBP_PlayerRadialMenu_C:CloseMenu` also stalled up to 187ms.
   - **Steady sources, all session:** nameplate sweep
     `FindAllOf("WBP_PalNPCHPGauge_C")` ~29/min (1.2–1.9s/min); player lookups
     `FindAllOf("PalPlayerCharacter")` ~27/min (1.1–1.9s/min; Trust tick,
     personality scan, and during fights the `PalHate:DamageEvent` hook, one
     61ms); personality scan `FindAllOf("PalCharacter")` 7–13/min;
     `FindAllOf("PalAISensorComponent")` 7–10/min (40–75ms).
   - **Why the sensor index still rebuilds:** `GetOrInitState` →
     `GetPresetClassName` tries `GetComponentByClass` (broken for this
     component), then goes straight to `find_sensor_component_via_index`,
     a world-wide rebuild at most every 5s. It never checks
     `cachedSensorByPalId`, which the `SelectResponseBySenses` hook already
     fills for practically every wild Pal nearby.
   - **Fixes IMPLEMENTED 2026-09-15 (approved by Dragón: "sure go ahead...
     the idea is that we polish it as much as we can"), harness-tested, in
     the dev install, NOT yet measured in game (run D):**
     (a) **`Scripts/PlayerRef.lua`** (new) — the only player lookup. Keeps
     the reference, IsValid on every use, re-searches when invalid, plus a
     **10s safety-net re-search** even while valid (a dead character can
     linger as a valid object after respawn), and waits 2s after a search
     that found nobody. Replaces Trust `find_player`/`find_player_name`,
     Combat `find_player`, Capture's 4 and Interaction's 3 `FindFirstOf`
     player lookups (incl. the radial redirect), and the personality scan's.
     (b) **Nameplates from the hook** (Indicator.lua, "NAMEPLATES FROM THE
     HOOK"): BindFromHandle puts the gauge in `pendingGauges`, every 2s tick
     runs `install_trust_bar` on those with no search, Unbind/invalid drops
     them. The world sweep runs every tick until the hook registers, 5 more
     ticks after, then **every 15 ticks (~30s) as a safety net**.
     Discovered while doing this: the sweep was the ONLY thing that created
     tags; the hook only recorded the Pal handle.
     (c) **Personality scan from the sense hook**: the hook records
     `pawnByPalId` and refreshes `lastSeenAt` (its early return now stores
     the Pal id instead of `true`); `senseHookArmed` is set on registration.
     Armed scans iterate those Pals (skip enforced ones, drop invalid) with no
     search; **every 8th scan (~64s) is the full world search as a safety
     net**; unarmed, every scan is the world search as before.
     (d) **Sensor cache first**: `GetPresetClassName(palActor, palId)` checks
     `cachedSensorByPalId` before `GetComponentByClass`/the index;
     `cache_sensor_for_pal` now caches BEFORE `GetOrInitState` (it was after,
     so every new Pal's first sense rebuilt the index);
     `SENSOR_INDEX_REFRESH_SECONDS` 5 -> 30.
     Tests: `tools/harness/perffixtest.js` (30 checks, both directions — the
     search is gone in the common case AND every fallback still searches),
     verified to fail against two deliberate regressions (cache order
     reverted; palId ignored). `hitcosttest.js` updated to the 10s semantics
     plus an invalid-player re-search check. **Harness limit found:** fengari
     has 32-bit integers, so the real `GetStableId` (`% 0x100000000` mask)
     always returns nil there — tests replace it; no earlier test had ever
     exercised it. All 13 existing suites, harness3 (14 hooks, identical),
     profiletest, syntax and both static checkers pass.
     **RELEASE WARNING (extends the profiler one):** both release trees need
     `Profiler.lua` (switch OFF) AND `PlayerRef.lua`, or the mod fails to
     load. Run C's profile log is archived at
     `perf-captures/runC-palbonds-profile.log`.
     **Run C frame baseline** (whole capture incl. a fast-travel load):
     avg 45.6 fps, 1% low 6.2 fps, 79 hitch events/min.
   - **Run D (2026-09-15 13:35–13:45, first fix round, profiler ON).** Dragón:
     "it felt a lot smoother". No Lua errors, 14 hooks. The frame capture was
     NOT recorded (the in-game F3 never reached PresentMon; no CSV was ever
     created). Profile (`perf-captures/runD-palbonds-profile.log`), per
     minute over the session: radial redirect 37 ms/min (was 3.2–3.8 s);
     player searches 6.2/min (the 10s safety net); nameplate sweeps 3.7/min
     (was ~29); personality world scans 1.3/min (was 7–13); world-search
     freezing ~0.67 s/min total (was 2.9–7.9). Remaining, in order:
     `update_trust_bars` 244 ms/min (138 frames >=8ms, every label
     recomputed every 2s); sensor index still rebuilt ~1.7/min (Pals the
     safety scan found but the hook never reported retried it every scan);
     radial `CloseMenu` 108ms mean / 140 max with no search involved; player
     safety net ~6/min up to 102ms; tags showing "?" longer (tags now wait for
     the hook or the ~64s safety scan); F8 Play 150ms once (controller
     search).
   - **Second fix round IMPLEMENTED 2026-09-15 (Dragón: "go ahead... the
     specifics or the code related things, i will leave that up to you"),
     harness-tested, in the dev install, awaiting run E:**
     1. `update_trust_bars`: bar written only when its ratio changed; label
        Pal id resolved once per actor; label-only tags rebuild text only on
        personality/F9-visibility change or every `LABEL_REFRESH_SECONDS`
        (10s); tags with a bar (bonding) still every tick.
     2. `try_enforce_personality(palActor, palId, cacheOnly)`: the hook-fed
        scan passes `cacheOnly`, so a Pal without a hook-cached sensor never
        falls back to the world-wide index there (the safety scan still can).
     3. Profiler sections inside `closeRadialMenuActionWindow` (pet grant,
        feed dispatch) to name the 108ms in run E.
     4. `PlayerRef` death/world-exit (Dragón's idea): IsDead/IsDying checked
        at most once per second; after a death the body is still returned
        while the world is searched every 2s until a DIFFERENT or living
        character appears; `Combat.ResetForNewWorld` calls
        `PlayerRef.Invalidate()`; safety net 10s -> 60s.
     5. A tag still "?" creates that Pal's personality on the spot
        (`GetOrInitState`, retried at most every `LABEL_STATE_RETRY_SECONDS`
        = 10s per Pal).
     6. `find_player_controller` reads `player.Controller` first; the world
        search is only the fallback.
     Tests: `perffixtest.js` now 42 checks (death/respawn, world reset,
     cache-only scan for a never-sensed Pal added), each new one verified to
     fail against a deliberate regression (cacheOnly removed -> 7 index
     rebuilds; death check disabled -> 4 respawn failures).
     `hitcosttest.js` moved to the 60s safety net. All 13 existing suites,
     harness3 (14 hooks, identical), profiletest, syntax and both static
     checkers pass. **Not yet in-game verified — nothing committed** (Dragón:
     GitHub only once in-game testing confirms the changes work).
     **Untested by the harness (widgets too deep to stub):** fix 1's label
     gating and fix 5's on-the-spot personality creation — watch tags in run E.
   - **Run E (2026-09-15, F3 at 14:35:06, second fix round, profiler ON).**
     Dragón: "felt slightly laggier than the previous one" (run D, which has
     no frame capture). Timeline: 2 min idle; moving + F9 tags on/off; fast
     travel + mount; bonding; new Pal + fight; new Pal + betrayal; fast travel
     + bond + death; respawn (the bonded Pal waited at the respawn spot, then
     died fighting a hostile). No Lua errors, 14 hooks. Captures:
     `perf-captures/runE-fixes2-1.csv` (full session) and `-2.csv` (1.8s,
     from an extra F3 — confirms extra presses create new numbered files,
     never overwrite), profile `perf-captures/runE-palbonds-profile.log`.
     Frame comparison over matching windows (`analyze-presentmon.js --range`):
     | window | 1% low | p99 | hitches/min | mod timer series |
     |---|---|---|---|---|
     | idle A (mod on, pre-fix) | 16.2 | 41.6ms | 81.6 | 2.05s/3.07s/8.1s |
     | idle B (mod OFF) | 36.1 | 26.3ms | 43.5 | none |
     | idle C (pre-fix, profiled) | 13.4 | 54.7ms | 117 | 2.05s/8.1s |
     | **idle E** | **33.2** | **25.4ms** | **39.0** | none |
     | bonding C 240-300s | 4.1 | 110ms | 91 | several |
     | **bonding E 240-300s** | **13.3** | **39ms** | **13** | none |
     | fighting C 420-480s | 5.7 | 111ms | 55 | 2.1s/8.2s |
     | **fighting E 300-360s** | **13.9** | **48ms** | **19** | none |
     **Idle with the mod is now within noise of the mod turned off.** The
     median frame time in E's play windows was HIGHER than C's (bonding 24.5
     vs 21.0ms) — the game itself was working harder in those areas, which is
     the likeliest thing felt as "laggier"; the mod's stutter dropped.
     Profile checks: player searches once a minute in play; death noticed
     ~14:43:37, respawn searches every 2-3s stopped ~14:43:57 when the new
     character was found; searches every 3s after 14:44:24 = the game closing.
     **Remaining mod stalls, biggest first (next candidates):**
     1. The ~64s personality SAFETY scan: 115-155ms in ONE frame — its
        `FindAllOf("PalCharacter")` (60-80ms) plus a sensor-index rebuild
        (55-70ms) via `GetOrInitState` for Pals with no cached sensor.
     2. Each feed: `do_real_wild_feed_via_worker_menu` 100-146ms (the whole
        radial CloseMenu cost; now named by the profiler section).
     3. Fix 5 (on-the-spot personality for "?" tags) hit the index twice,
        60-80ms each.
     4. Nameplate safety sweep ~every 30s, up to 95ms; player safety search
        once a minute, 40-96ms.
   - PresentMon capture `perf-captures/runC-profiled-1.csv` was still locked
     by a running elevated PresentMon at the end of the session (the game
     exited but `--terminate_on_proc_exit` did not close it). Stopping it
     needs an elevated command, i.e. a UAC prompt for Dragón.

## The 1.1.6 "Next steps" list (boss HP bars and the 20% calm-down)

This was the body of `## Next steps`, kept long after both items shipped. Item 0b
is the boss trust bar and personality tag (built and confirmed over runs 1 to 3,
2026-09-16). Item 0c is the "a Pal crossing 20% should stop attacking" work —
nine mechanisms tried, the brief-follow one that worked, and the crash it exposed.
Items 1 and 2 were the microstutter plan and the settings-screen decision, both
shipped. Replaced on 2026-09-28 by a real open list.

In order:
0. **DONE 2026-09-15 — v1.1.2 published to Nexus and the Steam Workshop**,
   verified on both pages and in the game's installed copy (see "Where we
   stand"). Kept for reference: it was done one store at a time, following
   "Publishing procedure" and "Publishing safety". The files are ready: `release/PalBonds-v1.1.2.zip` (Nexus) and
   `release/workshop/PalBonds/` (Workshop, Version 1.1.2). Both need the new
   `PlayerRef.lua` and `Profiler.lua` — already included. Changelog material:
   the README "Known issues" microstutter entry.
0b. **NEXT UPDATE (Dragón, 2026-09-15: "save this for tomorrow, it will be
   our next update we have to work on") — bosses show neither the trust bar
   nor the personality tag.**
   - **Symptom 1:** a boss Pal never shows its friendship/trust bar.
   - **Symptom 2:** a boss Pal never shows the personality it rolled.
   - **Same cause for both, in Dragón's words: "since they have a different HP
     bar".** What the code confirms: everything Indicator.lua draws attaches to
     the regular nameplate widget, `WBP_PalNPCHPGauge_C`. That covers the
     `BindFromHandle`/`Unbind` hooks, the `pendingGauges` install path, the
     world sweep `FindAllOf("WBP_PalNPCHPGauge_C")`, and `install_trust_bar`
     parenting into that widget's `ProgressBar_HP` panel. A boss's HP bar is a
     different widget, so nothing ever attaches to it.
   - **Found in the UE4SS CXXHeaderDump (2026-09-16), not yet seen live:**
     - `WBP_BossEnemyHPGauge_C` (parent `UPalUICharacterHPGaugeBase`, the same
       base as the normal gauge) has a direct `TargetCharacter` field and a
       `SetTargetCharacter(APalCharacter*)` function, so the Pal comes with the
       widget and no handle lookup is needed. Also `OnDead`, `OnRequestClose`,
       `Destruct`.
     - Its child `WBP_IngameBossHP` (`WBP_IngameBossHP_C`) is the visible
       top-of-screen bar: `BossGaugeHP` / `BossGaugeHP_Back` (ProgressBars),
       `Text_BossName`, `Text_LvValue`, `CanvasPanel_Prefix`, `SizeBox_Overall`.
     - The owner is `WBP_PalNPCHPGaugeCanvas`: `DisplayedBossUGaugeMap`
       (APalCharacter → gauge), `Add Boss Gauge`, `OnEndPlayBossPal`,
       `OnBossDead`.
     - The species flag is `UseBossHPGauge` (data table), plus
       `GetIsBoss`/`GetIsRaidBoss`/`GetIsTowerBoss`/`GetIsPredatorBoss`.
     - Plan: hook `SetTargetCharacter`, attach bar + tag inside the boss
       widget, clean up on `Destruct`/`OnDead`. Placement is Dragón's call.
   - **BUILT 2026-09-16, harness-tested (`bosstest.js`), deployed to the dev
     copy, NOT yet seen in game.** Dragón's calls: every boss type shows it
     ("i've been able to bond with all type of bosses so far"); the trust bar
     goes under the HP bar "like always, ideally with the same length too";
     the tag goes under the bar, as on nameplates. He flagged that several
     bosses stack their bars vertically, so the same offsets may overlap the
     next bar. `Indicator.lua` "BOSS HP BAR" section: hook-fed
     (`pendingBossGauges` → `bossEntries`), one `FindAllOf` only right after
     the hook installs, refreshed on the existing 2 s tick. Bar/tag go into
     `BossGaugeHP`'s own panel (the "BossHP" canvas). Bar height = 35% of the
     HP bar's, clamped 6–10. Tag style copied from `Text_LvTitle` (falls back
     to `Text_BossName`), height 22 — both guesses to check.
     `[BOSS-GEOM]` (diagnostics only) prints the real layout, nesting chain
     and clipping once per session.
   - **Run 1 (2026-09-16, Chillet alpha):** tag appeared ("Bonding"), trust
     bar invisible. Cause: `BossGaugeHP`'s slot is anchored, and
     GetPosition/GetSize returned (4,18)/(4,8) — raw offsets, where 4 is a
     RIGHT MARGIN, not a width. The bar was built 4px wide (a yellow dot at
     the left end of the HP bar in his screenshot). Fixed: our widgets now
     copy the HP bar's anchors and alignment and reuse its left/right
     offsets, so they get the same length either way; the HP bar is 8 tall
     at Y 18, so the trust bar sits at Y 28, 6 tall. `bosstest.js` A1b
     models the stretched layout and fails without the anchor copy.
     Nesting seen: `BossHP` canvas < `SizeBox_128` < `VerticalBox_94` <
     `CanvasPanel_BossHP` < `SizeBox_Overall` < `CanvasPanel_0`; clipping 0.
     Seen attaching to alpha, predator and ThunderBird bosses. Stacking with
     two bosses still untested.
   - **Design reminders:**
     - Bonding a boss already works (the raid-boss test, alpha x2 bar); only
       the display is missing.
     - Keep the 1.1.2 performance rules: hook-driven, no timed world sweeps, a
       rare safety net only.
     - The label-only vs bar entry logic and "owned Pals show no tag" must
       carry over.
0c. **Idea (Dragón, 2026-09-16, "just curiosity"): a Pal crossing 20% should
   stop what it was doing / stop attacking.** It is already coded:
   `Personality.MaybeBecomeFriendlyByBar` swaps the real AI preset to friendly
   and runs `interrupt_and_resense`, which cancels the current action, resets
   `ResponsedMaxBiologicalGrade` and re-senses. Two gaps: it has never been
   confirmed live on a Pal that was ATTACKING at the time, and nothing clears
   the Pal's hate target, so it may resume the fight. Only for unowned,
   not-yet-following Pals whose disposition wasn't already friendly.
   - **Third gap, found 2026-09-16:** a Pal that ROLLED Curious (internal
     "friendly") never gets the reset at all, because the function returns at
     its first check. The commenter's Curious attacker is exactly that case.
   - **Dragón's theory to confirm (2026-09-16):** the commenter's Timid Pal
     joined a same-species Hostile's fight (the joiner behaviour), and after
     the reset it simply joined again because the Hostile was still there.
   - **Spies in place:** `[WON-OVER-SPY]` in `Personality.lua` (diagnostics
     only): state before the reset, which path ran (reset / no reset and
     why), then the Pal's action and hate target every 2 s for 20 s, tagging
     the target `(THE PLAYER)` or `(SAME SPECIES)`. Remove once answered.
   - **Run 1 (2026-09-16), what the log shows (Dragón's own account still
     to compare):**
     - Chillet alpha (tracked 'notinterested'): reset ran cleanly; it was
       calm before and after (petting / looking at the player).
     - **Timid Lamball: NO reset — a real bug.** Its species preset is
       friendly, and `state.presetClassName` still holds that species value
       even though enforcement had swapped its real AI to a private escape
       preset. So the "preset already friendly" check skips the reset of a
       Pal whose real AI is NOT friendly. It kept attacking the player for
       the whole 21 s watch. Fix candidate: record the enforced preset in
       `presetClassName` (or check `enforcementApplied`/`rolledTier`).
     - Curious Chikipi: no reset (the rolled-Curious gap); attacked the
       player for ~10 s, then was being petted and started following.
     - Both reached 50% on the next pet (bar 125 at a 0.25x level gap) and
       followed while their hate was still on the player.
     - **Dragón's corrections (what really happened):** one pet took each
       Pal past 20% but under 50% (Lamball 23 s and Chikipi 10 s between
       Friendly and following — enough time; I misread this). The Lamball
       did NOT join the fight against the other Lamball: it stayed angry at
       him after bonding and he killed that Lamball alone. It only fought
       the Chikipi because a hit landed on it. The log misled me because
       `[HATE-ASSIST] pushed hate` is our command, and `fighting=true
       (follow suspended for a fight)` is our own flag — neither shows what
       the Pal actually did.
     - **NEW BUG (Dragón, 2026-09-16): a failed pet still grants points.**
       Both first pets were done mid-attack animation and visibly failed,
       yet `[BALANCE-TEST]` granted +50. The spy confirms it: both Pals were
       still in `BP_AIAction_CombatPal_C` 2 s later, whereas successful pets
       show `BP_AIActionPairCall_Petting_C` (Chillet; both second pets).
     - Hate API available: `UPalHate` has only `ChangeHate(Attacker, delta)`,
       `ForceHateUp_...`, `DamageEvent`, `AttackSuccessEvent`,
       `SelfDeathEvent` — no clear/reset function.
     - **Dragón's rules (2026-09-16):** (a) "friendly > curious": a rolled
       Curious Pal gets the 20% reset too. (b) "friendly means it shouldnt
       attack unless to defend itself or at least it should forgive if it was
       angry before." His scenario: Curious + Feral roam together, the Feral
       attacks, the Curious joins, the player kills the Feral, the Curious
       keeps attacking, the player gets it to Friendly → it must stop.
     - **BUILT 2026-09-16, harness-tested (`bosstest.js` B1–B5, C1–C3, D1,
       all failing on the previous code), deployed, NOT yet seen in game:**
       - `Interaction.lua` PET-CHECK: a radial pet grants only once the Pal
         runs `...Petting...` (polled every 250 ms, up to 4 s); otherwise
         "the pet never happened", nothing granted.
       - `Personality.MaybeBecomeFriendlyByBar`: every wild Pal crossing 20%
         gets the reset (Curious included); `real_preset_is_friendly` uses
         the rolled tier over the stale species `presetClassName`; the reset
         waits for a pet in progress to end (`when_not_petting`, 500 ms, max
         10 s); a successful swap sets `rolledTier = "friendly"`.
       - `Personality.ForgivePlayer`: `ChangeHate(player, -step)` with steps
         100, 200, 400… (max 12) while the player is the Pal's top hate
         target. Player only; logs `[FORGIVE]`, including "STILL angry" if
         ChangeHate has no effect (the real unknown for the next run).
         Called at the 20% reset and from `Combat.StartFollowing`.
       - `[LEASH-SPY]` now adds `REALLY: <action / hate target>` from
         `Personality.DescribeFight`, so our "follow suspended" flag is no
         longer mistaken for the Pal actually fighting.
     - **Run 2 (2026-09-16 15:38), Dragón:** boss friendship bar now shows
       correctly (two-boss stacking still to check). Won-over Pals kept
       attacking; the bonded Garm (alpha wolf) "never defended me once, nor
       even itself". Pet test inconclusive in the chaos; next time he pets a
       SLEEPING Pal, which should grant nothing.
     - **Run 2, what the log shows:**
       - The ChangeHate forgive is DISPROVEN: five calls, 12 steps and
         -409,500 each, the player still the top hate target every time; each
         won-over Pal attacked for the whole 20 s watch. Removed.
       - What does clear hate on the player: starting to follow. In both runs
         every new follower dropped it within ~3 s (PinkCat 15:43:25→:28,
         Lamball and Chikipi in run 1). The companion preset's player slots
         = Ignore are the only player-facing change → now applied at 20% too
         (see below).
       - Garm self-defence: `[SELF-DEFENCE]` fired against a Lifmunk
         (Carbunclo, a ranged shooter) and was released IN THE SAME SECOND,
         "its target is out of reach" — the reach rule (target further than
         1800 from the player → don't fight). Twice. The log now prints the
         measured distance. Open design question for Dragón.
       - During his fight with the wild Garm pack: hate pushes logged, 16
         combat installs, but REALLY showed the Garm in `WildLife` with no
         hate most of the time, wandering past 1800 → recalled twice. The
         long-standing wild-AI problem, not new.
       - PET-CHECK: 6 pets refused at 15:47:28–42 with the Pal in
         `BP_AIAction_Death_C` (which Pal isn't named; ask Dragón).
     - **BUILT after run 2 (harness B1–B5 fail on the run-2 code):** the 20%
       reset always writes a fresh friendly preset with `Discover_Player` and
       `Damaged_Player` = Ignore; once the Pal no longer hates the player
       (checked every 1 s, up to 20 s) `Damaged_Player` goes back to the
       friendly default so it can defend itself
       (`RESTORE_SELF_DEFENCE_AFTER_FORGIVING`, unverified whether that wakes
       the old hate). `[FORGIVE]` logs either outcome.
     - **Run 3 (2026-09-16 16:10), Dragón:** boss bar + tag CONFIRMED correct
       — "lets settle that for now" (three bosses at once is too rare to find;
       parked). Sleeping-Pal pet correctly gave nothing. Pals still attacked
       after Friendly. Lyleen boss pets didn't match the friendship gain.
       The run felt laggy. His calls: self-defence against ranged attackers
       YES, with the limit raised to 3000 ("before they touch the abandoned
       border"); and the next release is built from the shipped version plus
       these fixes, not this log-heavy dev build.
     - **Run 3, what the log shows:**
       - Player slots = Ignore alone does NOT stop it: the Lamball attacked
         for all 21 s; the Plant Slime "calmed" only by dying.
       - Lyleen (`BP_LilyQueen_GYM_C`): the 3rd pet was "confirmed after
         0.00s" because the 2nd pet's animation was still playing — paid
         twice. Also +10 passive gain between pets (50→60), which is the
         passive-bonding feature, not a pet.
       - The killed wolf: 6 pets refused while in `BP_AIAction_Death_C` —
         correct.
       - Lag: `palbonds-profile.log` put the two diagnostics-only FindAllOf
         (`PalUICharacterHPGaugeBase`, `PalUINPCHPGaugeCanvasBase`, run every
         2 s when SHOW_DIAGNOSTICS is on) at 676 stalls, mean ~145 ms,
         ~3.5 s/min — the dev build's biggest cost by far.
     - **BUILT after run 3 (bosstest B1/B4, C4, D fail on the run-3 code):**
       - FRIENDLY GUARD (`Personality.friendly_guard`): for up to 30 s after
         the 20% reset, every 500 ms, while the Pal's top hate target is the
         player and it isn't in a PairCall (pet/feed), its action is
         cancelled; stops when it calms down (then restores Damaged_Player)
         or starts following. Modelled on why followers calm down: the
         follow action keeps taking the slot.
       - PET-CHECK only pays a NEW petting animation (address differs from
         the one playing when the pet was chosen; never the same animation
         twice; without addresses, only after a non-pet read).
       - `SELF_DEFENCE_RECALL_DISTANCE = 3000` for self-defence fights
         outside player fights (reach check and recall); player fights keep
         1800. The out-of-reach message now prints the distance.
       - Removed the diagnostic panel scan and everything only it used
         (`check_panel_children`, `check_all_panels`, property dumps,
         `register_bind_hook_once`, `find_bind_widget_class_path`,
         `inspect_gauge_widget`) — Indicator.lua 2,483 → 1,881 lines.
     - **Also built after run 3, before run 4 (bosstest B6 and E fail on the
       previous code):**
       - Dragón's idea, "force them to do a rest_animation after reaching
         20% - one that interrupts shortly after they forgive the player":
         the guard, after cancelling an attack, starts PalRandomRest (77) on
         the character ActionComponent when that is idle, and cancels it once
         the Pal calms down (`FRIENDLY_GUARD_PLAYS_REST`, false = cancel only).
         Unknown: whether the fight AI respects a character action.
       - Boss x2 bond meter: run 3 showed `GYM_LilyQueen` (tower Lyleen) at a
         125 bar while `BOSS_LilyQueen_Dark` got 500 — the "BOSS_" prefix
         missed gym bosses. `Trust.is_boss_pal` now also accepts "GYM_",
         `_BOSS`/`_GYM` in the Blueprint class, and any Pal the boss-bar hook
         reported (`Trust.MarkBossActor`, which also drops a multiplier
         cached before the bar appeared). Only the Lyleen pair was bonded in
         run 3; the Centaurs, Lyleen and the predator Mummy were only seen.
     - **Run 4 (2026-09-16 17:33):**
       - Lamball (rolled Curious) attacked all through the guard: 60 AI
         cancels in 30 s, the rest animation started only ONCE (the
         character ActionComponent was busy almost every tick — its attacks
         run there), and the watch showed `CombatPal` with hate on the player
         at every 2 s sample. Cancel+rest is DISPROVEN as a way to stop it:
         the AI re-picks the attack at once from the hate it still has.
         Three mechanisms have now failed (ChangeHate, player slots Ignore,
         cancel+rest). The one that works every time is starting to follow
         (hate gone in ~3 s). Leading hypothesis, UNTESTED: it is the follow
         action's `Trainer = player` (a Pal does not keep hate on its own
         trainer — `FPalHateInfo.bEnabled`), not the slot-holding. Next
         experiment proposed to Dragón: at 20%, install the follow action
         briefly (the Pal walks to the player for a few seconds), then drop
         it. Needs his call — it is a visible behaviour.
       - Human NPCs (Dragón): all showed "Curious" in town. Cause: humans
         were kept out of the roll but their disposition fell back to the
         species default, and the VillageNPC preset maps to "friendly" →
         "Curious". FIXED: `state.isHuman` → disposition "normal" (tag
         Normal). Also found: the 20% reset had rewritten the AI preset of the
         three humans he petted (a SalesPerson and two MobuCitizens) — FIXED,
         humans are skipped (bosstest B7).
       - Raid bosses: the object dump has `BP_LegendDeer_RAID_C`; "RAID_" and
         "_RAID" added to the boss markers (bosstest E2). The boss-bar route
         also covers them, since raid bosses get the boss HP bar.
     - **Dragón, after run 4:** humans stay bondable AND capturable like Pals
       — "in order to let true pacifist runs play out". (Their AI is still
       never touched by the 20% reset.) Go-ahead for the brief-follow test,
       with "remove all the other things" so nothing else muddies it.
     - **BUILT for run 5 (bosstest B1–B5 and F fail on the run-4 code):**
       `Trust.StartBriefFollow(pal, hatesPlayer, onDone)` — at 20% the Pal
       gets the REAL follow (st.isFollowing + Combat.StartFollowing, so the
       companion preset and target discipline come with it), started at once
       while the pet is still playing (Combat won't install follow over a
       fight). Polled every 500 ms: released via Trust.StopFollowing once it
       no longer hates the player and ≥3 s have passed, or at 15 s; kept if
       the bar passed 50% meanwhile. On release Personality writes a plain
       friendly preset and re-senses (no cancel). REMOVED: the friendly
       guard, the rest animation, the player-slot overrides, the
       Damaged_Player restore, `when_not_petting`, `apply_forced_preset`'s
       overrides parameter. `Personality.HatesPlayer` is exported.
       Risks to watch: hitting the Pal during the brief follow counts as
       betrayal; `Combat.StopFollowing` is the betrayal/abandon removal path
       (Wait-swap etc.), now used for a friendly release.
     - **Run 5 (2026-09-16 18:57) — the brief follow ran, then the game
       CRASHED:** `EXCEPTION_ACCESS_VIOLATION reading 0x338`, GameThread, two
       UE4SS frames in the stack — the same signature as the world-change
       crash solved in pass 285 (docs/hook-points.md). Log: LEASH-SPY stopped
       after 19:08:36 (loops no longer serviced), a HUD widget push at
       19:08:40, then the crash — the old quit-to-menu pattern. Awaiting what
       Dragón was doing at that moment.
       - Brief follow worked mechanically every time: CuteFox, ChickenPal,
         PinkCat (via Play) released after ~3 s "NO LONGER angry"; SamuraiDog
         reached 51% during it and kept following. Whether they attacked
         after release: awaiting Dragón.
       - SUSPECT: the release goes through `Combat.StopFollowing` (the
         betrayal path), which could not remove the follow action ("still
         installed = true") and fell back to `Trainer = the Pal itself`. That
         left a self-trainer follow action on three wild Pals, where before
         today this path ran only on rare betrayals. A real follower was also
         present. Unproven; proposed A/B: follower-only + quit vs
         brief-follows-only + quit.
       - CuteFox release: "no readable sensor, friendly preset not written".
       - **Dragón's answers:** he quit the world and loaded it again → crash
         (the pass-285 world-change pattern). He then ran the A/B: **a real
         follower alone + quit/reload also crashes**, so the brief-follow
         release is NOT required — the world-change crash is back in the dev
         build. He is now testing the SHIPPED 1.1.2 Workshop copy (verified
         byte-identical to release/workshop, local dev copy disabled by
         renaming dwmapi.dll and enabled.txt to *.MODS-DISABLED) to see
         whether players are exposed, i.e. whether 1.1.2's microstutter work
         (PlayerRef keeping the player reference, hook-fed nameplates) brought
         it back.
       - Behaviour: the cat (PinkCat) visibly stopped attacking after its
         brief follow. The others reached the bond in one pet — Dragón's
         diagnosis: while a Pal is briefly treated as following, it gets
         passive friendship on top of the pet (he named the game's own +10;
         note also this mod's own follower passive gain in tick_followers).
         SamuraiDog went 50 → 51% during its 3 s brief follow. To fix: no
         passive gain during a brief follow.
     - As the log read it: the
       companion Lamball joined the player's fight against another Lamball
       (HATE-ASSIST), a hostile Chikipi attacked the companion Lamball
       (SELF-DEFENCE), the companion Lamball hit the new companion Chikipi
       once (FRIENDLY-FIRE), and that Chikipi ran up to ~1650 away while
       "fighting".
1. **DONE in v1.1.2 — Microstutters reported by a real user** (Goldaer,
   Workshop comment, 2026-09-14, against 1.1.0). Record kept below and in
   "Known open defects" #0. **Started 2026-09-15, plan agreed with Dragón.**
   Dragón confirms he feels the stutter himself with the mod active and had
   grown used to it. Note for when the next player reports anything: the
   `[RADIAL-REDIRECT-PERF]` line covers only the radial menu, and the verbose
   debug log narrates events without timing them — neither finds a stutter.
   The agreed plan:
   1. **Baseline, no code:** PresentMon (`Proyectos\_tools\PresentMon\PresentMon-2.5.1-x64.exe`,
      Intel-signed, needs elevation → a UAC prompt on Dragón's screen) records
      every frame to `perf-captures/` (gitignored). Same spot, standing still,
      2 minutes, PalBonds ON vs OFF (OFF = rename the dev install's
      `enabled.txt`; UE4SS stays loaded). Analyse spike count, 1% lows, and
      the spike **rhythm**.
   2. **Profiler: BUILT 2026-09-15.** `Scripts/Profiler.lua`, switch
      `local PROFILING = false` (shipped). When true, `main.lua` (which requires
      it FIRST) wraps the UE4SS globals — `RegisterHook`, `RegisterKeyBind`,
      `ExecuteInGameThreadWithDelay`, `ExecuteWithDelay`, `ExecuteInGameThread`,
      `LoopAsync`, `LoopInGameThreadWithDelay`, `NotifyOnNewObject`, plus the
      world searches `FindAllOf` / `FindFirstOf` / `StaticFindObject` — so
      every hook, timer and search in every module is timed with no module
      edits. Hooks are named by path, timers by source `File.lua:line`,
      searches by class. Manual `Profiler.start()/stop()` sections only in the
      personality scan (GetFullName / GetOrInitState / try_enforce per Pal) and
      the nameplate sweep (install_trust_bar loop, update_trust_bars). Output:
      `palbonds-profile.log` (gitignored by `*.log`), one report per 10s —
      per system calls / total / avg / max / >=8ms / >=16ms, then every call
      >= 8ms as a STALL line; times are inclusive. Each report prints os.clock
      elapsed next to wall elapsed: **if they disagree, the durations are not
      trustworthy** (see the os.clock doubt in Profiler.lua's header).
      Tested by `tools/harness/profiletest.js` (37 checks), which was verified
      to fail against two deliberately broken wrappers (returns dropped;
      report written mid-callback). fengari has no `io.open`, so the test uses
      an in-memory one.
      **Dev install has it ON** (only `Profiler.lua`'s switch line differs from
      `mod/`). **RELEASE WARNING:** `main.lua` now requires `Profiler.lua`, so
      `release/PalBonds/` and `release/workshop/PalBonds/` MUST get
      `Profiler.lua` with the switch OFF at the next release, or the mod fails
      to load.
   3. **One measured run** with profiler + PresentMon at the same spot.
   4. **Fix causes, never cut features.** Leading suspects, unmeasured:
      the 8s personality scan (`FindAllOf("PalCharacter")` +
      `FindAllOf("PalPlayerCharacter")` + a `GetFullName()` per Pal — the
      radial menu's own `FindAllOf("PalCharacter")` scan measured 36-74ms),
      the 2s nameplate sweep (`FindAllOf("WBP_PalNPCHPGauge_C")`), the ~2s
      Trust player-cache `FindAllOf`, and the always-on
      `SelectResponseBySenses` hook. Likely direction, to be confirmed with
      Dragón after measurement: track Pals and nameplates from the hooks
      that already hand them to us, so world-wide sweeps become rare safety
      nets. Confirm any suspect with an **in-session toggle**, not two runs.
   5. **Re-measure**, Dragón judges the feel, then 1.1.2 under the usual rules.
2. **Settings screen** decision: where the F9/F10 toggles and balance knobs
   would live. The last part of the Polish category.
3. **Multiplayer** only if Dragón wants it (see Pending).
4. **Bonded-Pal despawn** — parked as a known limitation, see below. Worth
   revisiting only with fresh eyes and a specific new idea, not by
   re-running the experiments already recorded there.

Deliberately NOT next: the controller swap (see "Two routes to the right
brain"), a fallback only, and the current approach works.


---

# Archived from CLAUDE.md on 2026-09-28 — the whole working file, verbatim

Dragón ordered this split after a shipped fix (the boss defeat record, live since
1.1.6) was reported back to him as open work, twice in one session. His diagnosis
was that the active file had become a mixture of current truth and dated
narrative, too long to read in one call, so a session would read part of it and
believe whatever it happened to land on. He also rejected the first attempt at a
remedy — leaving the stale sections in place under a warning — with the question
that settled the approach: *"what makes you believe that your future self wont
misinterpret or read it as how you try to mean it?"*

So `CLAUDE.md` was rewritten from scratch to hold ONLY current truth and the
rules that still bind. Nothing was summarised away: the entire previous file is
reproduced below, exactly as it stood, and remains the place to look for how any
particular thing was investigated or decided. It covers 2026-09-06 to 2026-09-28
— the performance work, the co-op work, the settings screen, the crash hunt that
produced 1.1.9, and every player report handled in that period.

**Read this file for history. Never read it for status.**

# 32 — PalBonds (behaviour mod for Palworld)

**Progress: 100%**

Dragón's ruling (2026-09-23): *"we are already past the 1.0.0 version, which I
would consider as the 100% - all the rest of things are just extras and add-ons
to the mod"*. The global rubric's own definition agrees -- 100% is "finished and
uploaded to its platform(s) for users" -- and PalBonds has been live on the
Steam Workshop, Nexus and GitHub since 1.1.0, with 1.1.7 (co-op) live on
2026-09-23. Everything after this point (the settings screen, releasing Pals,
further co-op verification, cleanup) is post-1.0 extras, tracked in "Pending"
and in the release sections, NOT as missing percentage.

| Category | Weight | Done | Contributes |
|---|---|---|---|
| Design and planning | 10% | 100% | 10% |
| Tooling (UE4SS + mod loading in game) | 15% | 100% | 15% |
| Hook research (the 6 open questions in DESIGN.md §8) | 15% | 100% | 15% |
| Per-individual personality system | 10% | 95% | 9.5% |
| Wild-Pal interaction (pet / feed / play) | 15% | 100% | 15% |
| Trust system | 15% | 100% | 15% |
| Following and combat assist | 10% | 95% | 9.5% |
| Threshold capture / flee | 5% | 100% | 5% |
| Polish and configuration | 5% | 85% | 4.25% |

Following stays at 95% for the open spawner-despawn defect. Polish counts the
README, both store descriptions, licence, screenshots, the Workshop upload, the
Nexus package and the Nexus publish as done (published on Steam, Nexus, and
announced in 2 Reddit posts, 2026-09-14; **v1.1.1 published to both stores
2026-09-15**; **v1.1.2 on GitHub, Nexus and the Steam Workshop 2026-09-15**;
**v1.1.3 on all three 2026-09-16**; **v1.1.4 on all three 2026-09-18**, GitHub
`8846dca`; **v1.1.5 on Nexus and the Workshop 2026-09-19**); only the settings screen is left. v1.1.4 (the Play crash fix and
20% forgiveness) moves no category. Recalculate whenever a category moves, and keep
the `Progreso:` line of this project's block in `../game proyects.txt` in sync.

**Microstutter note for the table:** the reported stutter WAS the mod's doing
(measured 2026-09-15) and is fixed in v1.1.2, so no category was moved; the
percentage stays as it was.

---

## WHAT IS OPEN — read "Next steps" and nothing else

This file is ~4,300 lines of dated narrative. Only two sections state status:
**"Next steps"** (what is open, what is closed, and why) and **"Known open
defects"**. Everything else is a record of how something was solved on a
particular day and goes stale the moment it ships.

Dragón's correction, 2026-09-28, after a 2026-09-19 "STILL OPEN" line was
reported back to him as current work even though the fix had shipped in 1.1.6:
*"you either forget to clean your stale informations / update and keep organized
your pending lists / or simply read the mds incomplete."* Closing what is done
is Claude's job, not a question for him. If a fix is verified, close it in the
same pass — and if an item cannot be observed or reproduced any more, close it
too: *"we open new things if we find them."*

## 1.1.9 IS LIVE (2026-09-27)

- **Nexus:** version 1.1.9, file "PalBonds V1.1.9", 124 KB (our zip is 127,278
  bytes), uploaded 1:40AM, virus scan Safe to use, 1 main file. Changelog and
  short description are Dragón's wording.
- **Steam Workshop:** updated 27 SEP 2:06, full changelog posted.
- **CurseForge:** uploaded, but **1.1.8 is still not approved there** — their
  moderation queue is far behind. Nothing to chase.
- **GitHub:** pushed, `630da5b..a865452`. The repo had been stale since v1.1.7,
  so that commit carries 1.1.8 as well. **No new issues; nothing further from
  Hakaishin** — issue #1 is still the only one and still closed.

**Store descriptions rebased from the live pages** into
`release/nexus-description.txt` and `release/workshop-description.txt`: the
Settings section now describes the in-game screen, and the "an in-game settings
screen is planned" promise is gone. Dragón edited the live pages himself and is
doing the other 15 languages separately.

**README updated, HELD FOR 1.2.0 (Dragón's call).**
`release/PalBonds/README.txt` now describes the in-game screen: the SETTINGS
section is rewritten, the keybind line says "rebound to any key in the settings
screen", the feature bullet names the screen as new in 1.1.9, the F9 note points
at what the screen says tags start as, and the "planned for a future update"
promise is gone. The settings file keeps a short paragraph — it is where choices
are saved and still hand-editable.

**MIND THIS:** `release/PalBonds/README.txt` now DIFFERS from the README inside
the shipped `PalBonds-v1.1.9.zip`, on purpose. The zip was not rebuilt and
nothing was re-uploaded. **Rebuild the zip when 1.2.0 is packaged** — until
then, the tree is ahead of what players have.

## 1.1.9 PACKAGED — was awaiting upload (2026-09-27)

`release/PalBonds-v1.1.9.zip`, 127,278 bytes, **18 entries, forward-slash
paths** (Compress-Archive writes backslashes — built with Python's zipfile
instead; the 1.1.7 notes already flagged this). `release/workshop/PalBonds/`
synced, `Info.json` Version **1.1.9**. Both trees md5-identical. 27/27 suites
pass against the stripped tree. **Nothing uploaded, committed or pushed.**

**Dev stack disabled at his request** (the standing "all the local mods" rule):
`Pal/Binaries/Win64/dwmapi.dll` -> `dwmapi.dll.MODS-DISABLED`, and
`Pal/Content/Paks/LogicMods/CreativeMenu.pak` -> `.MODS-DISABLED` (it would
otherwise load under the Workshop loader). No other proxy DLL present.
Re-enabling is HIS call, never Claude's.

### PERFORMANCE: A CORRECTION CLAUDE HAD TO MAKE TO ITSELF
The first comparison used `2026-09-24_runF-118-clean.csv` because of its name.
**runF is the PRE-fix measurement** — its 61 hitches/min is the "before" number
in this file's own 1.1.8 section ("61/min -> 30/min"). The shipped 1.1.8
baseline is `2026-09-25_runL-clean-fixed.csv`. Against the right baseline:

| flying, 2 min | 1.1.8 shipped (runL) | 1.1.9 (runJ 0-120s) |
|---|---|---|
| avg fps | 56.4 | 62.3 |
| 1% low | 20.9 | 22.2 |
| 0.1% low | 11.8 | 9.9 |
| p99 frame | 33.9 ms | 31.1 ms |
| worst frame | 107 ms | 138 ms |
| hitches/min | 30.0 | 27.5 |
| stall series | none | none |

**1.1.9 is level with 1.1.8, not faster.** Better on average and p99, slightly
worse at the extreme tail, hitches about the same — all inside run-to-run
variation on different terrain. **So the changelog must NOT claim a performance
win.** The trust-bar leak fix is real and measured (flat 11-21 entries vs
0->603 in 14 minutes) but needs a LONG session to matter, and a two-minute
capture cannot show it.

**Opening the settings screen costs nothing measurable** (runK): its first 30 s,
with the screen opened, were the *best* part of that run — worst frame 110 ms
against 445 ms for the later flying.

**Dragón's own read of the "laggy area", and it fits the data:** that zone is
one he rarely plays, so the game was streaming uncached resources; it improved
the more he played there. runJ's minutes 3-4 (that area) were genuinely worse
than 1-2 — 1% low 22.2 -> 16.6, hitches 27.5 -> 45.5/min, one 413 ms frame.
A weak ~11.4 s stall series showed up in that window only (6/10 slots, ~0.9 by
chance); shipped 1.1.8 shows none. Not enough to act on — noted, not chased.

## 1.1.9 RELEASE BUILD — built, tested offline, AWAITING DRAGÓN'S LONG RUN

`release/PalBonds/Scripts` rebuilt from `mod/` through
`tools/strip-comments.py` (22,097 -> 12,110 lines) and **deployed to the live
install as the thing that would actually ship**. Nothing is zipped, committed or
published — that needs his word.

Removed from the source for the release: `MENU_ENABLED` and `INPUT_PROBE`
(crash-investigation scaffolding) and `InputProbe.lua` itself. Verified off:
`DEBUG_LOGGING`, `SHOW_DIAGNOSTICS`, `TRACE_PHASES`, `ACTION_CHANGE_PROBE`.
27/27 suites pass against `mod/` AND against the stripped `release/` tree.

**This run has NO LOG, on purpose** — that is what a player gets, and it is the
build being tested. If anything goes wrong, redeploy `mod/` with
`DEBUG_LOGGING`/`TRACE_PHASES` on and reproduce.

### SLEEPING WILD PALS — asked 2026-09-26, answer: NO, and why
Dragón asked whether interacting with sleeping wild Pals could be a setting,
explicitly conditional on it being easy and not risking what works. It is not.

* **The game refuses, not us.** The radial substitution has no action-state
  gate, so the menu does appear; the game's own Pet/Feed simply will not run on
  a sleeping Pal, and `PET-CHECK` then correctly grants nothing because the
  interaction never happened. Recorded from his own run 3 (2026-09-16):
  "Sleeping-Pal pet correctly gave nothing."
* **Changing it means one of two bad things.** Either wake the Pal — pushing or
  altering an action on `UPalActionComponent`, which is the exact system that
  caused CRASH #2 on 2026-09-01 and the reason `play_refusal` still refuses a
  busy Pal to this day — or bypass `PET-CHECK` and grant friendship for an
  interaction the player can see did not happen, which breaks the contract the
  whole interaction model rests on.
* If it is ever wanted, the route is research: find the game's OWN wake
  mechanism and use that. Not an add-on.

## 40 MINUTES, NO CRASH (2026-09-26 19:44-20:24) — 1.1.9 candidate

Archived as `docs/bug-reports/2026-09-26_clean-40min-session.log` (12 MB, trace
on). Dragón played normally, opened the screen twice, bonded Pals.

| | before | this session |
|---|---|---|
| crashes | 4 in one evening; 14s and 3m45s with the screen open | **none in 40 min** |
| `LUA_ERRERR` in UE4SS.log | yes, 43s after the 154 armed | **zero** |
| tracked bars | 0 -> 603 in 14 min, straight line | **flat, 11-21 all session**, 146 prunes |
| trace pairs | `gauge.boss` 20/10 | every pair balanced except `gauge.boss` 40/20 |

**The one real finding, now fixed: the boss-gauge hook callback was unguarded.**
Entered 40 times, reached its end 20 -- exactly the 20 boss bars that attached.
UE4SS invokes it twice per call and the second invocation's parameters are not
the shape `hook_get` expects, so it threw. Nothing broke (the bar attaches on
the first invocation) but an exception raised twice a minute inside a hook is
not shippable, and every other hook in that file was already wrapped. Now
`pcall`ed, with a once-only log so a genuine failure stays visible.

**Known cosmetic gap, Dragón's call to leave it:** `SpaceBar` is refused because
UE4SS names that key differently and separator-stripping cannot bridge it. His
ruling: *"spacebar is already jump in the game, doubt anyone will swap such a
core key."* Note that the numpad very likely breaks the same way
(`NumPadOne` vs `NUM_ONE`) -- offered, not taken.

**NOT YET DONE for a release:** the clean build. `DEBUG_LOGGING`,
`TRACE_PHASES`, the trace call sites and the `MENU_ENABLED` / `INPUT_PROBE`
switches all have to come out, and the suite has to pass against
`release/PalBonds/Scripts` -- a stripped build is a build nobody has tested.

## FIRST LIVE RUN OF THE NEW REBINDING — two faults, both fixed (2026-09-26 14:21)

**1. "It locks me when the key fails, especially F1-F5."** The log names it four
times:
```
14:21:24  ignoring F6: it arrived before the screen finished asking
14:21:33  ignoring F5: ...   14:21:41  ignoring F4: ...   14:21:46  ignoring F2: ...
```
`CAPTURE_MIN_WAIT = 0.25` — a deaf period after the click. It was built for the
RegisterKeyBind mechanism, where UE4SS's registration burst could deliver a key
nobody pressed. **That mechanism is gone**, the overlay only reports a key it
actually received while focused, and the guard's only remaining effect was to
swallow the player's FIRST press and then keep holding the keyboard until he
pressed again. **REMOVED.**

Note for the record: it was **not** F1-F5. F5, F4 and F2 each appear in the
ignored list AND in the succeeded list seconds later — same keys, same session.
The variable was *speed*: a quarter second is inside human reaction time, and he
was going quickly down the F-row.

**2. The overlay came up in Japanese.** `KeyConfigParam` is deliberately nil (it
is what stops the widget rebinding a REAL game action), so the widget never runs
the game's own text setup and both of its blocks keep their design-time
defaults. Both are `BP_PalTextBlock_C`, so we now write them ourselves with
`SetText_GDKInternal` (rule 4 — a raw `.Text =` crashes this game): the title
becomes the row being rebound, the line under it
`"Press a key   ·   Esc to cancel"`. New Locale string `menu_press_key_cancel`
in 16 languages; Locale is now **75 strings**.

Covered: menutest asserts both text blocks are written in the player's language,
and that a key reported the instant the overlay is up still counts. 27/27.

## BUILT: the settings screen no longer registers a single key watcher (2026-09-26)

**157 key watchers -> 3.** `Menu.lua` now has zero `RegisterKeyBind` calls; the
only one left in the mod is Interaction's three gameplay hotkeys.

**How rebinding works now.** Clicking a rebind row builds the game's own
`WBP_OptionSettingsOverLayWindow_C` through the same `native_widget` path as
every other native widget on the page, fills it over `inst.page` at
`OVERLAY_Z = 90`, and focuses input on it. One class-wide hook on
`:OnKeySetting` reads the FKey out of the hook parameter. The handler checks
`GetAddress()` against the instance WE put up, so a rebind in the game's own
options screen cannot drive one of our rows. `KeyConfigParam` is left nil so the
widget's apply-logic has no game action to write to.

**`capturable()` was not deleted, it changed job.** It used to decide which keys
got a watcher; it now decides which reported keys are ACCEPTED. Escape cancels,
a mouse button or bare modifier is ignored and the screen keeps waiting.

**A real integration bug the tests caught, not the code review:**
`key_pressed`'s success path does not go through `stop_capture`, so the overlay
stayed on screen after a key was accepted. Fixed.

**AND THE ONE THAT WOULD HAVE KILLED THE FEATURE IN GAME:** the overlay reports
FKey names (`SpaceBar`, `LeftMouseButton`) while `RegisterKeyBind` needs UE4SS's
table (`SPACE_BAR`, `LEFT_MOUSE_BUTTON`). Uppercasing gives `SPACEBAR`, which
matches nothing — so **Space, the headline key the old approach could never
capture, would have been refused the moment it became capturable.**
`Settings.resolve_key_name` now matches on the name with separators stripped,
built lazily from whatever `Key` actually holds.

**Tests:** menutest's rebinding section rebuilt on the overlay — no watcher is
registered at all (`__BINDS` is empty with the page open), the overlay goes up
as a child of our canvas and comes back down on success, on Escape, on a second
click and on timeout, Space and W both bind, a fire from a foreign overlay
instance is ignored, mouse/modifier are refused while waiting, and the keyboard
is handed back on every exit path. 27/27 suites pass.

## SOLVED: ANY-KEY CAPTURE WITHOUT RegisterKeyBind (2026-09-26 13:54)

Six probe rounds, three of which crashed, ending in a confirmed mechanism.
Logs: `docs/bug-reports/2026-09-26_probe-round5-real-key-names.log` and the
round-6 confirmation.

**The answer is the game's own "press a key" modal**, found by grepping the
CXXHeaderDump for every widget class with a reflected key event:

```cpp
class UWBP_OptionSettingsOverLayWindow_C : public UPalUserWidgetOverlayUI
    void OnKeySetting(FKey NewKey);            // FKey as a HOOK PARAMETER
    FEventReply OnKeyDown(FGeometry, FKeyEvent);
    UWidget* BP_GetDesiredFocusTarget();
    UBP_PalTextBlock_C* BP_PalTextBlock_Title / _Command;
    UBP_HUDDispatchParameter_KeyConfig_C* KeyConfigParam;
```
Asset: `/Game/Pal/Blueprint/UI/UserInterface/MainMenu/Option/`
`WBP_OptionSettingsOverLayWindow.WBP_OptionSettingsOverLayWindow_C`

It takes focus, receives `OnKeyDown`, and passes the pressed key to
`OnKeySetting` as a plain parameter. Hooking that returned clean names:
**`W`, `SpaceBar`, `R`, `G`, `H`, `U`, `S`** — including the two keys
DarnMenu's curated battery explicitly cannot bind. Game thread, no
`RegisterKeyBind`, no struct crossing the boundary by value.

It also sits in the SAME asset family our settings page already builds from
(`WBP_OptionSettings_*`), so using it keeps the game's own look and focus
behaviour instead of imitating them.

**The rule learned across all six rounds — write this down:**
- **CALL** a function taking/returning an FKey-bearing struct by value →
  **the process dies** (AV 0x70; rounds 1 and 2, two different functions on two
  different objects, identical fault).
- FKey nested in a struct with **no reflected members** (`FKeyEvent`) → a clean,
  catchable Lua error (round 3).
- **HOOK** a function and **READ** an FKey as a parameter or as a UObject
  property → **works** (rounds 4-6).
- A UE4SS `FName` needs `:ToString()`; `tostring()` prints the userdata address
  (`Capture.lua:168` has said so all along — round 4 lost a run to it).

**Free bonus:** the same hooks expose the game's own action names and their
current bindings (`MoveForward`/`Forward`->`W`, `Jump`->`SpaceBar`), which is
ready-made conflict detection for a future "that key is already Jump" warning.

### Next: build it (NOT yet started — Dragón's call on the design)
Plan: when a rebind row is clicked, construct the overlay, add it to our page,
let it take focus, read the key from the `OnKeySetting` hook, close it.
**Leave `KeyConfigParam` nil** so the widget's own apply-logic has no game
action to write to — the one real risk is a constructed instance rebinding a
REAL game binding, and a null parameter is what prevents it. Must be verified in
the first test run that no game binding changes.

**Still open and not addressed by any of this:** the three gameplay hotkeys
(F8/F9/F10). The modal needs focus and there is none during normal play, so
those stay on `RegisterKeyBind` — i.e. player-level exposure, minus the 154-way
amplification that is crashing Dragón every few minutes.

## THE KEY IS READABLE FROM A HOOK (2026-09-26 13:37) — route found

**All four hooks on the game's own rebinding widget armed and fired, and the
FKey's name resolved.** Log archived as
`docs/bug-reports/2026-09-26_probe-round4-keynames-resolve.log`.

```
hooked :OnKeyUp / :On Action Key Changed / :On UI Action Key Changed / :On Key Config Changing
KeyConfigChanging -> first FName param = 'FNameUserdata: 0000022C43B4B068'
ActionKeyChanged  -> action='FNameUserdata: ...' | NewKey.KeyName = 'FNameUserdata: ...'
OnKeyUp           -> CachedSettingKey.KeyName = 'FNameUserdata: ...'
```

`FNameUserdata: <address>` is **not** a failure — the property read SUCCEEDED
and returned a real FName wrapper. `tostring()` on a UE4SS FName gives the
userdata address; `:ToString()` gives the text, which `Capture.lua:168` has
documented since it was written. Round 5 fixes only that.

**What this establishes, and it is the thing three crashes were spent looking
for:** an `FKey` is reachable from Lua **as a property, inside a hook** —
`widget.CachedSettingKey.KeyName` and the `NewKey` hook parameter both resolved.
It is only unreachable when it has to cross the boundary **by value in a call**
(rounds 1-2, both fatal) or when nested in a struct with no reflected members
(`FKeyEvent`, round 3, a clean error).

**The rule that falls out of all five rounds:**
- CALL a function taking/returning an FKey-bearing struct → **process dies**.
- HOOK a function and READ an FKey property off a parameter or a UObject →
  **works**, and when it does not, it fails as a catchable Lua error.

So the capture route for any-key rebinding is: a UMG key event delivers the
press, and the key's identity is read as a property. No `RegisterKeyBind`.

**Still open:** the three gameplay hotkeys (F8/F9/F10). `OnKeyUp` needs a
focused widget and there is none during normal play, so nothing here replaces
them yet.

## SELF-INFLICTED: the InputProbe crashed the boot (2026-09-26 13:11) — FIXED

`InputProbe.lua`, written to answer "can a key press be read from the game
thread", **took the game down before it finished loading.** `AV reading 0x70`.
Removed from the live install within minutes; the probe is `INPUT_PROBE = false`
in `main.lua` and the file stays in `mod/` only. Evidence archived as
`docs/bug-reports/2026-09-26_probe-boot-crash.{log,runtime-xml}`.

The log's last line was the probe's own capability-pass header, so it died on
the **first native call**. Two bugs, both worth not repeating:

1. **A failed read was treated as success.** The guard was
   `local remote = safe(function() return c.Player == nil end)` /
   `if remote ~= true then return c end`, and `safe` returns nil when the read
   throws — so `nil ~= true` handed back a controller too broken to read a field
   off. **Every gate must require a positive confirmation, never "not false".**
2. **It ran before the player was in the world.** The line immediately before
   the crash is Session's "still loading — asking again until the player is in
   the world". The controller object existed while its internals did not, so the
   call dereferenced a null `PlayerInput` — `0x70` is a field at a small fixed
   offset off a null base, the shape `docs/hook-points.md` already describes.

Galling detail: this violated the freshness rule copied into that same file's
header from DarnMenu's notes two messages earlier — *only touch objects the
engine handed you recently*. A boot-time `FindAllOf` is the textbook case of a
poll discovering something unbuilt.

**Fixed in `mod/`:** a `world_is_ready()` gate (PlayerRef valid, not
world-closing, held for 2s) before anything native; `live_controller` now
requires `Player` AND `PlayerInput` to both read and validate, and hands both
objects to the candidates so none re-reads a field; and **a crumb is logged
before every individual native call**, so a repeat names the exact call instead
of just the pass. Not redeployed — Dragón's call whether to spend another boot.

## WHAT DARNMENU DOES ABOUT KEYS — checked, and it is NOT a better route (2026-09-26)

Dragón asked whether the reference mod has a safer way to capture a free key
press. **It does not. It uses the identical mechanism, with a shorter list.**
From `DarnMenu/Scripts/main.lua:496-678` and `DarnMenu_API.md:159`:

- A one-time battery of `RegisterKeyBind` calls over a **curated ~69-key set**,
  armed lazily on first use, gated by a capture flag — the same shape as ours,
  which arms 154.
- It documents the two hard UE4SS limits: **no any-key listener**, and
  **keybinds cannot be unregistered.** The second one kills the idea of arming
  watchers only for the duration of a capture — registrations would accumulate
  on every capture with no way to release them.
- It documents the cost of the short list: **Space, Enter, Tab, Esc, arrows,
  symbols and modifier combos are not capturable.** That is precisely the
  restricted key list Dragón rejected at milestone 4 ("on the keybinds you set
  it as options? really?... thats awful"), so copying it walks back his call.
- `ui.lua:3138` carries their own crash note: a keybind callback that touched a
  UObject **crashed their game**; their rule is the same marshal-first we
  already do — which UE4SS issue #1345 says is too late by construction.

**Their docs are still worth mining — three techniques we do not use:**
1. **`IsValid()` does not prove SAME object.** Freeze `GetFullName()` when a
   wrapper is accepted, compare before every use, evict on mismatch. Directly
   applicable to our cached actors (`trackedBars`, `pawnByPalId`, `FollowerActors`).
2. **"Every crash our instrumentation ever attributed was inside a TIMER poll.
   Zero were inside hook callbacks."** An object a hook hands you was vouched
   for at that instant; one a poll discovered is stale by construction. **This
   is a caution against the polling fix proposed above** — it must re-acquire
   the controller fresh, not cache it.
3. **Compare crash stack OFFSETS before trusting any log-tail attribution** —
   two of their "obvious" suspects were exonerated by byte-identical stacks
   appearing with the suspect disabled.

**Applying #3 to our five crashes:** no two are identical. crash1/crash2 share 8
offsets, run3 shares 7 with them and 9 with crash3, run2 shares almost nothing.
But **four of the five have their top frames inside the same UE4SS region
(`bcd`–`bdd`)**. Scattered fault points within one subsystem is what a corrupted
VM looks like; a single broken call site would give a repeating stack. That
supports the concurrency theory — and note we still have **no crash stack from a
run with the suspect disabled**, because run 1 simply never crashed.

## RUN 3: THE LUA VM IS PROVABLY BEING CORRUPTED (2026-09-26 12:31)

Crash while flying, `EXCEPTION_ACCESS_VIOLATION reading 0xffffffffffffffff`,
39 UE4SS frames over a deep Palworld chain — the crash-1/2 shape. Archived as
`docs/bug-reports/2026-09-26_run3-menu-on-AV-flying.log` and
`2026-09-26_run3-menu-on-AV.runtime-xml`.

**The find is in UE4SS.log, not the trace:**

```
12:28:17.848  [Menu] page opened / any key can now be bound (154 key(s) watched)
12:28:18.091  [ENFORCE] the sense budget skipped 53 sense(s) in the last second
12:29:00.324  Error: [Lua::call_function] lua_pcall returned LUA_ERRERR
                                          => error in error handling
12:31:59      crash
```

**`LUA_ERRERR` is an error raised while handling an error** — the classic
fingerprint of a `lua_State` whose stack has been trampled, which is what
concurrent use of one VM produces. It appeared **43 seconds after the menu armed
its 154 key watchers**, and the game limped on for three more minutes.

**Second corroboration in the same run:** `gauge.boss` = 20 entries,
`gauge.boss.done` = **10**. Ten boss-gauge hook invocations entered Lua and
never came back out. Every other traced pair balances exactly
(`gauge.bind` 159/159, `gauge.unbind` 151/151, `sense.enforce` 166/166,
`cache.stableid` 166/166).

**Scoreboard across the three trace runs:**

| | screen never opened | screen opened (run 2) | screen opened (run 3) |
|---|---|---|---|
| lasted | 15 min, clean | 14 s | 3 m 45 s |
| `sense.get` | 15,842 | 353 | 5,283 |
| VM damage | none | died inside `Context:get()`, `abort()` | `LUA_ERRERR` + 10 lost hook calls |

**What the trace did NOT do this time, stated honestly:** run 3's last line is
`sense.addr`, which is *also* the normal early-out for the ~97% of senses that
hit the address dedup — so it is ambiguous between "died inside
`sensor:GetAddress()`" and "returned normally and the crash was elsewhere".
**Instrumentation gap to close:** add one trace immediately AFTER the
`GetAddress()` call so those two cases are distinguishable.

**The leak fix is confirmed working.** Tracked bars per scan this run:
0 → 22 → 49 → 61 → 50 → 55 → 30 → 13 → 24 — it plateaus and oscillates, with 50
`[PRUNE]` lines actively releasing. Run 1 at the same elapsed time was at ~287
and climbing in a straight line to 603.

## RUN 2 RESULT: THE TRACE NAMED IT, AND DRAGÓN WAS RIGHT (2026-09-26 03:13)

**Crashed 14 seconds after the settings screen was opened.** Log archived as
`docs/bug-reports/2026-09-26_run2-menu-on-TRACE-CRASH.log`, crash context as
`2026-09-26_run2-menu-on-abort.runtime-xml`.

**The trace pinned the exact call.** 353 `sense.get` lines, 352 `sense.addr`
lines — exactly one unmatched, and it is the last line in the file:

```
[T0001017 52.147] sense.get      <-- no sense.addr ever followed
```

`sense.get` is written immediately before `Context:get()` in the
`SelectResponseBySenses` hook (`Personality.lua`). The process died inside that
call. Every other one of the 352 completed.

**The contrast is the result:**

| | Run 1 (screen absent) | Run 2 (screen opened) |
|---|---|---|
| duration | ~15 min | ~14 s after opening it |
| `sense.get` calls | 15,842 | 353 |
| keybind watchers | 3 | **157** (3 + the menu's 154) |
| crash | none | yes |

03:13:01 `page opened` + `154 key(s) watched`; 03:13:15 abort. Run 1 survived
forty-five times as many sense calls with the screen gone.

**New signature: `Abort signal received`, not an access violation** — a C++
exception escaping into `std::terminate`, which a Lua `pcall` cannot catch. But
the stack shares frame `UE4SS+bd59e3` with crash 3 (00:13), the one whose shape
matches all three player reports. Same subsystem, two ways of dying.

**Mechanism (now the working theory, was speculation last turn): a race on the
Lua state.** `RegisterKeyBind` callbacks run on **UE4SS's own thread** — this
file already knew that, it is written in `Menu.lua`'s own comment at the capture
block. The handler marshals its *work* to the game thread via `on_game_thread`,
but the `if capturing == nil then return end` check still executes in the Lua VM
on UE4SS's thread. With 157 watchers and keys held down while flying, that
happens constantly, and the game thread is simultaneously inside `Context:get()`
in the sense hook. Two threads, one `lua_State`.

**This also explains the players**, which is what makes it more than a menu bug:
Esaeon, Swordfish and Hakaishin have **three** keybinds registered permanently
(F8/F9/F10 via Interaction's `bind_key`) and no menu at all. Same race, roughly
fifty times rarer — which is exactly "rare", "after a while of simply running
around", and "seconds after the third pet".

**So reducing the count is not the fix.** Three is already enough to crash
players. The fix has to get the mod's key handling off UE4SS's thread entirely,
or make the handler never enter the Lua VM from it. Options, none chosen yet
(Dragón's call):
1. **Immediate mitigation:** stop arming the 154 watchers — returns Dragón to
   player-level risk, does not fix players.
2. **The real fix:** read key presses from a game-thread source instead of
   `RegisterKeyBind` (a hooked game input function), so nothing enters Lua off
   the game thread. Would fix the player crashes too. Needs research first:
   confirm UE4SS's dispatch model, and find a usable game-side input hook.

**Before committing to option 2, verify the threading claim properly** rather
than inferring it from stacks with no game frames.

## ACTIVE: THE CRASH — Dragón reproduced it himself (2026-09-26)

**This is the open player crash, not a new one, and it is now reproducible on
Dragón's own machine.** That is the thing this project has been blocked on
since 19 September, waiting for players to test for us.

**Four crashes in one evening, three with a full Windows crash context**
(archived as `docs/bug-reports/2026-09-26_dragon-UECC-*.runtime-xml`, and the
last run's live log as `2026-09-26_dragon-crash4-petallia.log`):

| # | Time | Dragón was doing | Address | Stack shape |
|---|------|------------------|---------|-------------|
| 1 | 23:50:08 | flying, watching Pals | `0xffffffffffffffff` | UE4SS ×9 ← **Palworld ×5** ← UE4SS |
| 2 | 00:04:40 | flying again | `0x24b31c9a909` | UE4SS ×9 ← **Palworld ×5** ← UE4SS |
| 3 | 00:13:02 | boss Lyleen following | `0x0` | **ucrtbase memcpy** ← UE4SS ×15, no game frames |
| 4 | 00:41:07 | bonding a Petallia | — | UE4SS dump only, no context file |

**Crash 3's shape is Esaeon's and Hakaishin's** (CRT `memcpy` on top, UE4SS
Lua frames below, no game frames, reading `0x0`). Different UE4SS builds so the
offsets differ, but the shape is the same, and Hakaishin's was singleplayer
with PalBonds alone. **Crashes 1 and 2 are a second shape**: Palworld frames
*underneath* the UE4SS frames, i.e. the game called a hook, which called our
Lua, which died.

**Ruled out — the settings screen / keybind capture.** Dragón's own theory, and
the stacks kill it: a UE4SS keybind fires on UE4SS's own thread with no game
frames below it, which is not what crashes 1 and 2 show. For crash 4 the log is
direct: capture ran 00:38:31→00:38:32 and ended cleanly, then two and a half
minutes of normal play before the crash. The Q/E tab-steal leaves the capture
sitting and waiting; it holds nothing and touches no game object.

**Working hypothesis (NOT established):** a cached `UObject` pointer read after
the engine recycled that address. Three *different* faulting addresses (`0x0`,
`-1`, and a misaligned heap address) is the signature of reading a field off an
object of the wrong type, not a null we forgot to check. UE4SS's `IsValid()`
returns true for a recycled address, so every `IsValid` guard in the mod passes
and the read still goes to garbage. The `memcpy` on top of crash 3 fits:
building a Lua string from a garbage FName length.
**Prime suspect: the `SelectResponseBySenses` hook** (`Personality.lua`) —
fires from deep in the game's AI for every Pal that senses anything, dedupes on
raw addresses (`handledSensorAddresses`) and holds pawns in `pawnByPalId` /
`cachedSensorByPalId` between prunes. Flying = maximum actor churn = maximum
address reuse, which is crashes 1 and 2. The crash run's log shows it saturated
("the sense budget skipped 2… 4… 8 senses in the last second").

### The trace run — BUILT AND DEPLOYED, awaiting Dragón's test

`Logger.trace` (built 2026-09-20 for Esaeon, never used by us) now writes
through its **own** path: no `print` (UE4SS's console is the expensive part of a
log line), no `os.date`, a monotonic sequence number, and the per-line flush
kept — the last line written is the operation that killed the process.
Self-tested against the deployed file (format, sequence, detail, flush count).

Trace points added at the hook entries and cached-pointer loops that had none:
`sense.*` (step level, one line per engine call — the suspect), `cache.*`,
`gauge.bind.*` / `gauge.unbind.*` / `gauge.boss.*`, `bar.entry` (Indicator's
tracked-bar loop, keyed), `trainer.step` / `trainer.follower` (after the
early-out, so a flight with no follower stays silent), `dmg.reaction`,
`dmg.hate`.

**The settings screen is OFF for this run — Dragón's call**, as the experiment
that confirms the analysis instead of arguing it: `MENU_ENABLED = false` in
`main.lua`, and `Menu.lua` renamed to `Menu.lua.DISABLED-crash-test` in the
deployed copy so it cannot load at all (Interaction's `WaitingForKey` lookup
fails safely — no screen means nothing is ever waiting for a key).
- still crashes → the screen is cleared, read the trace lines.
- does not crash → the screen or something shipped with it IS involved.

**Deployed to the manual install only**
(`Pal/Binaries/Win64/ue4ss/Mods/PalBonds/Scripts/`), with `DEBUG_LOGGING` and
`TRACE_PHASES` both true. That is the copy that actually runs: `dwmapi.dll` is
present, its files are current, and it is the one that wrote tonight's log. The
Workshop native-mods copy is a stale release build whose loader is not running
(exactly one `mod loading` line in UE4SS.log). **Release staging was
deliberately NOT touched** — this is a diagnostic build.
Tests: 27/27 suites pass against `mod/`; 26/27 against the deployed copy, the
one failure being `menutest`, which fails *because* the menu is gone.

**To restore afterwards:** `MENU_ENABLED = true` in `main.lua`, copy `Menu.lua`
from `mod/` into the live install (the parked `Menu.lua.DISABLED-crash-test`
there is now stale — it is only a marker), and set `TRACE_PHASES = false`.

### RUN 1 RESULT (2026-09-26, ~15 min): no crash, and it found a real leak

Dragón flew and watched Pals for about fifteen minutes with the screen off and
the trace on. **No crash.** That does NOT clear the settings screen — nothing
reproduced, so the comparison has no result either way; what the run actually
bought us is the leak below. 196,115 log lines, 11 MB, no errors, and zero
`PalBonds/Menu` lines, so the switch-off genuinely took.

The sense hook, the prime suspect, came out well: 15,842 calls but only 677 got
past the cheap address dedup — a 96% early-out. It is not the hot path.

**89% of the run was one loop.** `bar.entry` fired 139,454 times. Tracked bars
per scan, over the flight: 0 → 56 → 215 → 339 → 467 → 584 → 603, a straight
line with no plateau. 636 entries created, ~603 still alive at the end, and the
first Pal whose nameplate he saw fourteen minutes earlier was still being
re-validated every two seconds.

**Dragón connected it to something he had reported weeks earlier** — the game
feeling laggier the longer he played — which had been blamed at the time on the
debug log accumulating. That explanation was never measured and was very likely
wrong. This one is measured.

**FIXED (2026-09-26), `Indicator.lua`:** the tracked-bar cache now expires.
`TRACKED_BAR_UNSEEN_PRUNE_SECONDS = 60.0`. Presence is read from
`gaugeHandleByKey` — the bind hook fills it, the unbind hook clears it — so an
entry whose nameplate is on screen refreshes itself with **one table lookup and
no reflection**, and an entry left behind ages out. On prune,
`release_tracked_entry` detaches our bar and label from the pooled gauge (the
same `RemoveChild` pattern `reparent_existing_bar` already uses) and frees
`barInstalledForGauge` for that gauge, compared by address. Keeping the entry
past its gauge's recycle is still deliberate — that is what
`reparent_existing_bar` reuses — the cache just has an expiry now.
`Indicator.BindCounts()` gained a third return (the tracked-bar count) so the
table is countable from outside.

### RUN 2 — Dragón's call, and he was right to insist (2026-09-26)

Claude argued the menu-on comparison was not worth doing because it would
probably also not crash. Dragón: *"but if we turn the log on and i do exactly
the same thing as before and if it does crash, wouldnt that help us prove that
maybe the menu or something on the menu's new code is causing the crash?"* That
is correct and the objection was lopsided — it weighed only the null outcome. A
crash in run 2 would be the strongest evidence this investigation has had.

**THE SCREEN HAS TO BE OPENED for the run to test anything.** `arm_capture()`
runs from `open_page`, not from `Menu.Init`, and it is the only place the ~154
`RegisterKeyBind` calls happen (guarded by `captureArmed`, so once per session).
A run with the menu present but never opened does not exercise the new code.

**Mechanism worth taking seriously — a Lua-state data race.** Each of those 154
watchers fires on **UE4SS's own thread** for every key press for the rest of the
session (the handler's own comment says so). While flying, keys are held down
constantly. If UE4SS's keybind thread enters the Lua state while a game-thread
hook is already in it, that is a race on the VM, and a corrupted VM produces
exactly the signatures seen: `memcpy` on a garbage length, reads of `0x0` and
`0xffffffffffffffff`. **It would also explain the player reports**: they have
three keybinds registered permanently (F8/F9/F10 via Interaction's `bind_key`),
so the same race, roughly fifty times less often. Untested speculation, but it
fits every data point including the ones the menu cannot be blamed for.

**Correction to the earlier analysis:** ruling the keybind path out was right
for crashes 1 and 2 (Palworld frames present = game thread) but NOT for crash 3,
whose stack has no game frames at all — which is what a UE4SS-thread crash looks
like. The shape does not discriminate there.

**Run 2 protocol:** menu ON, leak fix ON, trace ON. Open the PalBonds screen
once at the start. Fly the same way for **30+ minutes** — run 1 was ~15 min and
crash 4 came 28 minutes into its session, so run 1 may simply have been short.
The leak fix stays ON deliberately: the leak is now a known confound, so
removing it makes a crash more attributable to the menu, and run 1 had the leak
present without crashing.

Covered by **perffixtest section D** (8 checks), which tests both directions as
that suite's header requires: a nameplate still bound is NOT pruned after ten
minutes, an unbound one is kept for 30s so reuse still works, past the window it
is dropped AND its widgets are detached, the gauge can host a Pal again
afterwards, and a 25-Pal flyby tracks all 25 in view and releases all 25 once
they are behind you. Verified to fail against the unfixed code (3 checks fail,
25 entries stuck). 27/27 suites pass; deployed.

## TOMORROW STARTS HERE (end of 2026-09-20)

**Today shipped 1.1.6 to all three places and then spent the rest of the day on
multiplayer.** Everything below is committed but NOT released: players still
have 1.1.6.

**State of the machine:** manual dev install ENABLED (`dwmapi.dll`,
`enabled.txt`), Workshop mods unticked, the game copy carries `mod/` with
`DEBUG_LOGGING = true` AND `SHOW_DIAGNOSTICS = true` (Dragón's standing rule:
in dev mode use whatever logging the work needs; strip it at release). `mod/`
itself has both false. A local Palworld **dedicated server** (Steam tool, free)
is installed and is how a GUEST session is tested without a second person.

**Built today, in order:**
1. **Which player is ours** — every lookup prefers the locally controlled
   character. Live-verified; the engine answers the question on this build.
2. **A Pal bonding with another player is left alone** — detected from the Pal
   (its follow action names a player who is not us), refused in the radial menu
   (before any food is spent), in Play and in the grant; `tag_claimed` in all 16
   languages. Harness-tested only: needs two real players.
3. **A guest's copy does nothing** (`Scripts/Session.lua`, NEW FILE — it must
   reach both release trees and the zip at the next release, the PlayerRef.lua
   trap from 1.1.2). Three live runs to get right; the last one is clean.
4. **Duplicate "starts following you"** fixed (pointstest P13).
5. **Missing trust bar after a reload** fixed (worldchangetest I).

**Verified by Dragón in game:** 1, 3, 4, 5 and the singleplayer regression of
all of them. **Not verified:** 2 (needs a friend).

**Next, in his stated order:** multiplayer, then the in-game settings screen,
then releasing Pals back to the wild ("an extra out of scope from this
project"). **Corrected by Dragón 2026-09-23:** that order was never a queue to
wait in -- "if we cannot continue developing multiplayer because we still need
some tests and another player to do so, then we simply advance with whatever we
can". Blocked work never blocks the rest. The immediate options are written up in
`docs/multiplayer-questions.md`:
- a two-player session with a friend (the only thing that can confirm the claim
  system and answer what each player sees);
- or investigate `ChallengeCapture_ToServer` and the other 335 `*_ToServer`
  RPCs, which is how a guest could ever do anything — testable alone on the
  dedicated server.

**The rubric does not move today:** multiplayer is not one of its categories and
nothing in the shipped feature set changed. Recalculate when the settings screen
lands or when co-op becomes a real, released feature.

## 1.1.7 BUILT AND READY TO PUBLISH (2026-09-23) -- Dragón's go-ahead

Co-op ships. His reasoning: no friend with a PC has been found, one machine has
tested everything it can, so players become the test ("what if we ship it and
just let players themselves tell us if they can now play with it or not").

Built and verified before packaging:
- `Session.ALLOW_GUEST_INPUT = true` (was `GUEST_INPUT_PROBE`, shipped false).
  Set it to false to put a guest back to 1.1.6 behaviour.
- The guest-food hole closed: a guest names the inventory slot to charge, so
  the owner now checks that container is that player's OWN (their inventory
  data's six container ids) before taking anything.
- Server test settings file deleted (it had `Pet = 125`); source defaults
  untouched at 50.
- All 24 suites pass AGAINST `release/PalBonds/Scripts` itself, not just
  `mod/`; hoist 2 / undef 4 known false positives; no dev flag on anywhere.
- PERFORMANCE, measured not guessed (PresentMon, `perf-captures/2026-09-23_*`):
  singleplayer 1.1.6 = 73.1 fps avg / 1% low 35.4 / 11.5 hitches per min;
  the co-op build = 77.1 / 41.0 / 7.5. No repeating stall series in either, so
  no timer of ours stutters the game. As a guest on the local dedicated server:
  66.0 / 42.3 / 4.5 standing still, and 54.7 / 17.7 / 24.0 while actually
  playing (hitches spread evenly, none periodic -- action-triggered work, the
  radial-menu target search being the known 40-80 ms one). Dragón's earlier
  "significantly laggier" was dev logging + the UE4SS console, both off now.
- Release trees, zip and README updated: `release/PalBonds` and
  `release/workshop/PalBonds` hold the 14 scripts (the three new files are
  `Net.lua`, `HostView.lua`, `Session.lua`), `Info.json` Version 1.1.7,
  `release/PalBonds-v1.1.7.zip` (17 entries, forward-slash paths),
  README has a new MULTIPLAYER section.
- Both installs (game + server) now hold the EXACT release scripts, logging
  off, for a smoke run. The dev `Logger.lua` (DEBUG + diagnostics true) and
  `ue4ss/UE4SS-settings.ini.devconsole-backup` restore development conditions.
- **NEXUS: LIVE** (2026-09-23, 10:08PM page time): version 1.1.7, one main
  file "PalBonds V1.1.7" (330 KB = our zip's 338,680 bytes), Dragón's six-line
  changelog as agreed, his own short description. Page description untouched.
- **WORKSHOP: prepared, not uploaded.** The upload folder
  (`steamapps/workshop/content/1623730/3797816321/`) and both installed copies
  (`Mods/NativeMods/UE4SS/Mods/PalBonds/Scripts`, `Mods/ManagedMods/PalBonds/
  Info.json`) carry the 14 release scripts and Version 1.1.7, BOMs kept,
  `.workshop.json` untouched -- so his Workshop test runs the real 1.1.7.
- **Dev stack DISABLED for that test:** `Pal/Binaries/Win64/dwmapi.dll` and
  `ue4ss/Mods/PalBonds/enabled.txt` both renamed `*.MODS-DISABLED`. Undo both
  to develop again.
- NOT done, waiting on Dragón: the Workshop upload itself; GitHub (commit,
  release); and deleting `release/PalBonds-v1.1.6.zip` as previous releases did.
- KNOWN UNTESTED at ship time, by anybody: two real players at once (claims,
  one leaving mid-bond), a hosted world where the host also plays, the dungeon
  RESYNC, and whether the guest's own food count updates on screen.

## 1.1.8 SHIPPED TO NEXUS + CURSEFORGE (2026-09-25)

**Nexus LIVE, verified on the page:** header 1.1.8, file "PalBonds V1.1.8",
100 KB (our zip is 103,270 bytes), uploaded 3:56PM, Dragón's changelog and his
short description. **CurseForge: a THIRD store now** -- he uploaded there too
and says moderation takes a long time to approve a file. **Workshop LIVE**,
verified after his test run (`last_published_version` 1.1.8).

**What 1.1.8 is, beyond the clean-ship pass below:**
- **The mounted-identity bug, found the day of release.** On a mount the
  player's own character answers `IsLocallyControlled = false`. PlayerRef's
  `Get` was fixed for that first (the game names our character:
  `UPalUtility::GetPlayerCharacter`), but `IsRemote` and `OwnerKey` still
  believed the engine, so while riding the mod treated Dragón as ANOTHER
  player: his F9 toast and every "left behind" message went into the co-op
  network path ("could not send MSG to a player: no controller") instead of
  onto his screen, and the second F9 press CRASHED
  (`EXCEPTION_ACCESS_VIOLATION`, log at
  `docs/bug-reports/2026-09-25_f9-mounted-crash.log`). Identity is now a
  comparison against the character the game names. The `IsLocallyControlled`
  fallback still exists for co-op, but is unreachable in a singleplayer
  session (`Session.ModeIfKnown()`), so the lie can no longer reach the
  network path where it crashed. Removing the fallback outright was tried and
  broke co-op in 28 checks -- that is why it is fenced rather than deleted.
  Regression test: nettest H0.
- **Performance, measured (perf-captures/2026-09-2[45]_*):** flying, the mod
  went from 25.3 s of game-thread time per 2 minutes to 3.9 s; hitches with
  the mod on went 61/min -> 30/min against 17/min with it off; the false
  world-wipes while flying (27 nameplate bars, 39 personality records, once a
  live follower) are gone. Fixes: the world change is detected from the game's
  own loading events (`LoadingFinished`, the loading-screen widget) with the
  old poll demoted to a 10 s safety net needing two misses; Session no longer
  asks UEHelpers for the world (it walked the object list looking for a
  PlayerController, 43 ms a call); the sense hook has a refilling per-second
  budget; the nameplate sweep builds at most 4 bars per tick.
- **Dragón's verdict before shipping:** tested singleplayer and as a guest,
  nothing broken, toasts and abandonment correct, no crash.

## SETTINGS SCREEN — milestone 9: the polish pass (2026-09-25)

**THE KEYBOARD HOLD WORKS.** Confirmed live: with the phantom-capture bug fixed
there was finally a real capture for it to block, and `SetInputMode_UIOnlyEx`
does stop the game acting on the key being chosen. **Except Q and E.**

### Q and E, and why they are different
They are the game's own menu-tab navigation, routed through its UI layer --
above where input mode reaches, because input mode governs GAMEPLAY input. There
is no Lua-reachable way to consume a CommonUI action. The binding itself still
takes; what leaked was the tab moving underneath our page. Mitigated rather than
fixed: after a key is chosen, everything the page covers is covered again, so it
is never left sitting over a tab the player did not choose. **Excluding Q and E
from being bindable was deliberately NOT done** -- that is the "limiting which
keys the player may have" that Dragón rejected on 2026-09-25.

### The rest of the pass
- **Play now refuses a switched-off personality.** It does not go through the
  radial menu, so the substitution gate that hides Pet and Feed could not cover
  it -- it earned nothing, but the animation still played. "Immune" should mean
  immune.
- **A rebind row is lettered like the rows around it.** It is the one row whose
  label the mod draws itself, at its own size; the size is now read from the
  first native row built and reused, so it cannot drift from the game's.
- **Nothing is said when a change simply works.** The note line printed the
  setting's INTERNAL NAME and value -- code words in front of a player, about a
  row they can already see. It is now only used for the two things a row cannot
  say by itself: a refusal (named the way the player sees it, not by its key)
  and "Saved".
- **`PassiveGainEnabled`**, a switch in Modules: where passive friendship gain
  STARTS, the same shape as ShowPersonalityTags. The key still toggles it for the
  session, and it is per machine while the toggle stays per player, so a guest's
  key still only switches their own followers. The toggle's own message no longer
  claims it returns to ON next launch -- it returns to the setting.

37 settings across 6 sections. All 25 suites pass; menutest 176 checks,
settingstest 208.

## SETTINGS SCREEN — milestone 8: the rebind bug, and balancing (2026-09-25)

### The rebind was binding a key nobody pressed
Dragón: *"i never pressed the d for rebind, it changed to that the first time
automatically"*. The log has it exactly: `any key can now be bound (154 key(s)
watched)` and `Play is now D` in the SAME SECOND, six seconds after the page
opened -- i.e. the instant he clicked the rebind button.

**Cause:** `arm_capture` ran inside `begin_capture`. Registering ~150 key
watchers is not instantaneous -- UE4SS's own thread fires them a moment later --
so that first burst arrived when `capturing` had ALREADY been set, and was taken
as the player's answer.

**And this explains the second symptom too.** *"if i try to change it to a key
that already does something in the game, it triggers the game instead of setting
a new key"*: the spurious capture ENDED the capture and handed the keyboard back
within milliseconds, so the key he then actually pressed reached the game
normally. One cause, both complaints. **Whether `SetInputMode_UIOnlyEx` really
blocks input has therefore still never been tested** -- there was never a live
capture for it to block. The log now says `holding the keyboard while a key is
chosen` when the call succeeds, so the next run answers it outright.

**Fix:** the watchers are armed when the PAGE OPENS, so the burst lands while
nothing is waiting and is ignored; plus a 0.25 s settle window, so nothing that
arrives in the same instant as the click can ever be an answer. Both pinned by
tests. (It had to be `open_page` rather than `build_page`: `arm_capture` is
declared below build_page and a Lua local declared further down is not in scope
above it -- the same lexical-scope trap this file has now hit three times.)

Cost of arming earlier: a player who opens the screen once carries ~150 inert
watchers for the session. Each returns on a single nil test when nothing is
waiting.

### The bonding switch was reading the wrong field
Switching Feral off did nothing to the Feral Pals in front of him. It was keyed
on `GetRolledTier`; **the tag the player sees comes from `GetDisposition`**, and
they are not the same: a Pal whose SPECIES is already Kill_All is kept out of the
roll and carries `rolledTier = "normal"` while wearing the Feral tag. Now keyed
on the disposition, using Indicator's own `PERSONALITY_DISPLAY_NAMES`
vocabulary, so the switch and the tag can only ever agree.

**And the option no longer appears at all** (*"it should fail from the beginning,
not even letting the option appear at all"*). The game's radial menu only offers
a WILD Pal because of the mod's own `TryGetSpawnedOtomo` substitution, so
refusing to substitute a non-bondable Pal means there is nothing to refuse later:
no Pet, no Feed, no Play, and no food spent finding out.

### Balancing (his numbers, both confirmed against the code first)
- `MAX_FOLLOW_DISTANCE` **3000 -> 3500** (Trust.lua) -- the distance a follower
  starts losing trust at and is eventually abandoned.
- `PLAY_HAPPY_FOLLOWUP_DELAY_MS` **6000 -> 5000** (Interaction.lua) -- Play's
  animation follow-up. A stale comment in Trust.lua calling it "Play's 3000ms"
  was corrected while in there.

### The two fruits
They now carry the game's ENGLISH item name in brackets wherever the label is
not already English -- "Fruta de afecto (Kinship Peach)", "Kleine
Zuneigungsfrucht (Little Kinship Peach)". His instruction, and the reasoning is
worth keeping: this project has never had the item's real name in the other 15
languages, and a translation of our own invention leaves a player unable to tell
WHICH item a row means; the English name is the one they can match against a
guide or the wiki.

## SETTINGS SCREEN — milestone 7: a personality can be switched off (2026-09-25)

Dragón: *"i was thinking of adding a check if a personality can be bonded or not,
for players that maybe dont want some personalities to be interactable at all
(like feral or aloof, etc)"*. Built. The screen now carries **36 settings across
6 sections**.

**Layout (his pick, asked before building):** each personality is now two rows --
its chance, then a switch directly under it reading "Curious — can be bonded", so
a personality's two settings are always read together. The label is composed from
`labelPrefix`, which puts the tag's OWN translated word in front of one shared
string: seven switches cost one new translation, and the switch can never end up
worded differently from the tag on the Pal's head.

**What such a Pal shows (also his pick):** the tag, but no bar. The tag is how
the player knows to leave it alone; a bar that could never fill would read as
broken. Switching one off mid-session hides the bars already on screen.

**Where it is enforced, and why there:**
- `Trust.MayBond` -- the function that refuses an interaction BEFORE any food is
  spent, so a switched-off personality never costs the player an item.
- `Trust.AddPoints` -- the funnel every points path in the mod ends in, as the
  backstop, so nothing can slip past by taking another route.
- **Unknown means allowed.** A Pal that has not rolled a personality yet is never
  refused by a switch that cannot apply to it.

**Tested:** a Feral Pal earns points with its switch on and nothing at all with
it off, through MayBond and AddPoints both; another personality is untouched;
every tier the roll can produce is checked to HAVE a switch (so one cannot be
silently unswitchable) and each switch to be a real setting; and the row is
verified to sit directly under its own chance, named after its tag, translating
with the rest of the screen.

## THE TWO WORDS: trust vs friendship — SETTLED, DO NOT "FIX" (2026-09-25)

**The settings screen says FRIENDSHIP points. The toasts still say TRUST. That
is deliberate and it is Dragón's ruling, not an inconsistency to tidy up.**

His reasoning, which is the part worth keeping: *"we are doing this for the
settings to not confuse the players, they already know the base game as trust
points and ranks, so if we call our bar 'trust' to modify, they may think they
will be modifying the trust from the base game instead of our made up points"*.

So the rule is about WHERE the word appears, not which word is right:
- **On the settings screen**, where a player is changing numbers, ours must read
  as *friendship points* — otherwise they think they are editing the base game's
  trust stat and that the mod is reaching into vanilla systems.
- **In the toasts and messages**, during play, "trust" keeps reading naturally
  and there is nothing to confuse it with, so the shipped strings in 16 languages
  stay exactly as they are. Asked directly whether to change them: *"dont think
  of changing the toasts messages"*.

## SETTINGS SCREEN — milestone 6: the two switches cover everything (2026-09-25)

A disabled trigger that still shows its message reads as a broken setting, so
each switch now turns off everything the player would otherwise see:

- **Abandonment off also silences the despawn message**, in both places it can
  come from (the loading-screen flush and the despawn path). Dragón: *"lets let
  them just asume their pals despawned and thats it"*. The Pal is still gone --
  the game despawned it -- the player is simply not told it gave up on them.
- **Betrayal off means a hit costs NOTHING.** Not a smaller penalty and not a
  penalty without the ending: no points lost, no trust-shaken effect, no
  betrayal. His framing: *"lets consider it as an on/off to reduce friendship
  points from player hits"*. The test is the first line of
  `Trust.OnFollowerDamaged`, ahead of everything that is a penalty in any form.
- `trigger_enabled` moved up to sit beside `BONDING_TRIGGER_THRESHOLD_BASE`,
  because the world-change message asks it far earlier in the file than the
  bond-loss path does.

Tested behaviourally: with betrayal off a Pal keeps every point through six
hits and no shaken effect fires; with it on the points drop. All 25 suites pass.

## SETTINGS SCREEN — milestone 5: second screenshot pass (2026-09-25)

Eleven items from a live test. All done; all 25 suites pass (menutest 162
checks, settingstest 176).

### The bugs
- **Save now saves WITHOUT closing.** It used to close, and with the page gone
  the only feedback was the screen vanishing -- which reads exactly like "save
  doesnt save, instead quits the screen". It writes, says "Saved" on the page,
  and stays. **And saving now moves the point Cancel goes back to**, or a Cancel
  after a Save would have undone the values just written to the file.
- **Changing the language rewrites the screen in front of you.** The subtitle
  promised it and it did not happen. Every label, heading, hint and button is
  registered as it is built and rewritten from Locale on a language change, and
  the lists rebuild their own choices. **The reason it silently did nothing at
  first: `refresh_texts` was defined AFTER `sync_control`, so the upvalue was nil
  and its own `pcall` swallowed the failure** -- forward-declared now.
- **The rebind row no longer overflows the list.** It was a HorizontalBox, which
  inside a ScrollBox is given as much width as its children ask for, so the
  fixed-width button hung past the right edge and was clipped. It is an Overlay
  now: it fills the width it is GIVEN and right-aligns the button, clear of the
  scrollbar.
- **Hovering no longer rebinds.** `WBP_OptionSettings_MenuButton_C`'s delegate
  fires on HOVER -- Dragón could not move the mouse across the screen without a
  row demanding a key. The rebind buttons are now `WBP_MenuESC_Button_S_C`, the
  class this file already proves is click-only (the entry, Save, Cancel and
  Restore defaults all use it).
- **The keyboard is held while the screen waits for a key.** Pressing the
  inventory key opened the inventory instead of binding it. UE4SS cannot swallow
  a key, but the engine can be told to stop routing input to gameplay:
  `SetInputMode_UIOnlyEx`, which is what the game's own modal screens use. Our
  bindings are UE4SS-level and still fire, so the key can be read without the
  game acting on it. **Every exit path hands the keyboard back** -- a chosen key,
  a second click, the page closing, the menu being destroyed -- **and an 8 s
  timeout on top**, because the one unacceptable outcome is a player who cannot
  move. All five paths are tested.

### The wording
- **Ours are FRIENDSHIP points.** Dragón's rule: the game's own UI calls its stat
  trust points, so naming ours the same points the player at the wrong system.
  The section is "Friendship points" in all 16 languages.
- **"While a Pal follows you" → "Passive friendship gain while following".**
- **"Display" → "Modules"**, on the screen and in a freshly written file.

### The new settings
- **Modules:** `AbandonmentEnabled` and `BetrayalEnabled`, both switches. The
  gate is inside `on_follower_lost_all_trust`, the single point both endings pass
  through, ahead of everything it guards; with one off the bond survives and the
  points are floored at 5% of the bar so the same check cannot fire again on the
  next tick.
- **Accessibility (new section):** `BarColor`, `TagColor` (including "same as the
  name", which is what it has always been) and `TagSize`. A new schema kind,
  `choice`, validates a value against a list the entry itself carries, so the
  file, the screen and the check all read the same one. The tag size is a SCALE
  on the Pal's own name font, so it is right at any UI scale. Changing any of
  them redraws the Pals already on screen (`Indicator.RefreshAppearance`).
  - **hoistcheck earned its keep twice here:** the colour table and then
    `compute_trust_bar_color` were both left BELOW code that reads them, and a
    Lua local declared further down resolves to a nil global -- the tag colour
    would have silently never applied.

### Open
- **The toasts still say "trust"** (`passive_on`, `passive_off`, and the bond-lost
  messages). Those are shipped text in 16 languages; the terminology rule above
  implies they should say friendship too, but rewriting live player-facing
  strings is Dragón's call, not a silent edit.
- The two fruit labels still name an in-game item in wording of our own.
- Nothing is committed or pushed.

## SETTINGS SCREEN — milestone 4: Dragón's screenshot pass (2026-09-25)

He sent a screenshot of the working screen plus a list. All of it is done.

- **Language is first** now, on the screen and in a freshly written settings
  file (the LANGUAGE block moved to the top of SCHEMA; an existing file keeps its
  own order, and the in-place save finds a key by name, never by position).
- **Every interaction and every food shares one 0..1000 scale, step 10** (Pet,
  Play, FeedBase, the five rarity bonuses, both fruits), and **the passive drip
  has its own 0..100, step 1** -- his numbers, after using the first version.
- **The title, the subtitle and the note line are centred TEXT, not centred
  boxes.** That was the bug in the screenshot: a TextBlock draws left inside its
  slot, so a slot centred on the canvas still leaves the words off to the left.
  `SetJustification(1)` on each, and they span the panel rather than a fixed 700.
- **Three buttons at the bottom: Save, Cancel, Restore defaults.** Cancel is only
  possible because the page snapshots every value when it opens; it restores that
  snapshot live and then `Settings.Discard()`s the pending writes, so the file is
  untouched. Save writes and closes. Restore defaults applies the shipped values
  live and deliberately LEAVES THE PAGE OPEN, so the player can still cancel out
  of it. Bulk restores run in two passes, because "Play = F8" is refused while
  Tags is still sitting on F8 and succeeds once it has moved.
- **The language list shows language names** (Español, 日本語, ...) instead of
  the codes the screenshot showed -- a code name in front of a player is the same
  mistake as the labels were. The stored value is still the code.
- The last row can scroll clear of the bottom edge (a trailing spacer), and the
  rebind buttons sit inside their rows instead of filling them edge to edge.

### Two guards added after looking at his live settings file
His file came back with a lot of zeros. The file itself was **structurally
perfect** -- same 88 lines, same 51 comment lines, every comment in place -- so
the save path is sound, and the values were his own test drags. But the
inspection surfaced two ways this screen COULD have done it by itself, and both
are now closed and tested:
1. **A row is not believed until it hands back the value we put in it.** A native
   row that has not laid out yet can report 0, and the watch would have taken
   that for the player's choice and saved it -- a settings screen that empties
   your settings just by being opened. Bounded to 5 tries so a value a widget
   genuinely cannot hold is followed rather than fought forever.
2. **A value already outside the screen's range widens the row instead of being
   clamped.** The file's bounds are far wider than the screen's, so a hand-edited
   Pet = 5000 would otherwise have been clamped to the slider maximum and then
   saved back at that clamp, quietly rewriting a number the player chose.

`menutest.js` is now **135 checks**, covering all of the above including Cancel
restoring, defaults applying without closing, the widened row, and the
not-ready-widget guard (the fake can now refuse to accept a seeded value).

### Still his call
- **A backup of his settings from before this screen existed** is at
  `save-backups/PalBonds_settings.before-live-screen.lua`. His live file now
  holds test values; Restore defaults in game will reset it, or the backup can be
  copied back.
- Whether the FILE's own 0..100000 ceiling is worth tightening now that the
  screen has sane ranges. Left alone deliberately: narrowing it would make the
  mod refuse a value a player already has and replace it with the default.
- The two fruit labels still name an in-game item in wording of our own.
- Nothing is committed or pushed.

## SETTINGS SCREEN — milestone 3: REBUILT after Dragón's first look (2026-09-25)

His verdict on the first version was that it needed *"a lot of polishing"*, and
every point was right. **The root mistake: the whole screen had been derived
mechanically from the settings schema** — labels from the internal keys, a slider
for every number, each slider's range from the file's validation bounds, and a
fixed list of keys to rebind to. A data structure describes what the program
needs; a screen describes what a person needs. Do not generate the second from
the first. (Saved as a standing memory.)

### What he said, and what was done about each
1. **"showing the label names we used on the file should not be like that ...
   lets keep the labels easy to understand and far from code names"** — every row
   is now a written label. Each schema entry names a Locale entry (`label =
   "set_pet"`), and **the seven personality rows reuse `tag_normal..tag_feral`**,
   the exact words the player already reads over a Pal's head, so the screen and
   the tags can never drift apart. A test asserts that no row shows a code name.
2. **"the settings themselves should change language when one changes
   languages"** — 24 new Locale entries in all 16 language sets (the labels, the
   five section headings, the rebind prompt and the "changes apply right away"
   line). `localetest`'s completeness check covers them like every other string;
   its count canary went 26 → 50.
3. **"you didnt even use the same style of the game ... the name palbonds gets
   half cut in between the tabs above and the button touches the border"** — the
   page is now framed with the game's own `WBP_PalCommonWindow_C`, inset from
   every edge, with the title and the Close button clear of both. The title was
   being cut because the first version hid three of the menu's panels and **the
   ESC menu's own tab strip (`Canvas_TabSet`) kept drawing over the page.** All
   seven panels the menu can show are now covered — each one's own visibility
   remembered first, so closing restores exactly what was there, including a
   panel that was already hidden and is not ours to reveal. Row height is 48 with
   8 between, matching the game's own Options rows.
4. **"you went crazy with sliders ... it was impossible for me to try and set pet
   to anything a bit higher than 50, just a small movement went to the thousands
   already, and why you put a max of 100000?"** — the 100000 is the FILE's
   validation bound and always was (1.1.x), not something invented for the
   screen; the mistake was using it as a slider range. **The schema now carries
   two ranges per setting:** `min`/`max` for what the file accepts, and
   `ui.min/max/step` for what the screen offers. The file's bounds stay wide on
   purpose — narrowing them would make the mod refuse a value a player already
   has and silently replace it with the default. The screen's ranges are sized
   against the trust bar being 500 points at equal level: Pet/Play/Feed 0–250
   step 5, food bonuses 0–100 step 5, the fruits 0–1000 step 25, passive 0–25
   step 1, join bonus 0–200000 step 5000 (friendship ranks really are that big),
   chances 0–100 step 5. A test asserts **no slider has more than 60 stops** and
   that every default lands exactly on a step.
5. **"on the keybinds you set it as options? really? ... so we are also limiting
   players which keys they can change to? thats awful"** — gone. A key row is now
   the label plus the game's own small option button showing the current key;
   click it and **press the key you want**. Reading an arbitrary press means
   UE4SS must hold a binding on every key, so it does — but only from the moment
   the player first opens this screen, never at mod load, and each handler
   returns immediately unless the screen is waiting. Mouse buttons and modifiers
   are excluded (a click on the button would otherwise become the binding, and
   Escape belongs to the menu). Clicking twice gives up. **And while it waits,
   the mod's own keys hold still** (`Menu.WaitingForKey`), or choosing F8 for Play
   would also play with a Pal on the way in.

### Why the key row is not the game's own key row
`WBP_OptionSettings_ListContent_C` *can* show a key, but only through
`SetKeyIcon(InputType, Key)` and `SetConfigButton(ActionName, FilterType,
InputType)` — an engine `FKey` and one of the game's OWN input actions. A mod's
keybind is neither, so pretending otherwise would mean inventing engine key
objects. The label + `WBP_OptionSettings_MenuButton_C` pairing keeps the game's
styling without that.

### Tests
`menutest.js` is now **110 checks**: the labels (no code names, the friendly
text, the tag reuse, and the whole page in French), the control shapes, the
screen's ranges and steps with the "aimable" and "default lands on a step"
rules, the rebind flow end to end (button shows the bound key, no key watched
until asked, click prompts, any ordinary key takes, Escape/mouse/modifiers
refused, clicking twice cancels, a clash refused with the button still honest),
the cover-and-restore of all seven panels, and the save on close. Plus the
`Menu.WaitingForKey` check on both sides (`settingstest` asserts Interaction
consults it). All 25 suites pass against `mod/` and the deployed copy;
`realfilecheck.js` still passes against Dragón's real settings file.

### Still open, and worth his eye rather than my guess
- **The margins are design-unit guesses** (window inset 300/96/300/56, list
  344/238/344/188). They cannot be verified offline; they need a look.
- **Two labels name an in-game ITEM** (`set_peach_lesser`, `set_peach`,
  written as "Small kinship fruit" / "Kinship fruit"). The project has never had
  the game's own item name in the other 15 languages, so these are descriptive
  rather than copied — the same kind of wording he corrected for the tag names on
  2026-09-18.
- Nothing is committed or pushed.

## SETTINGS SCREEN — milestone 2: the live settings layer (2026-09-25)

**Dragón, after testing milestone 1:** *"test run done and saw the palbonds
button, looked neat, so good job ... now lets try to see if you can add the
settings we currently have and we can make them work and change mid-game"*. He
also subscribed to Better Mod Manager so its files could be read.

### DONE and fully tested: a setting can now change while the game runs
This was the real prerequisite (the old "Pending" note said so). All 25 suites
pass against `mod/` and against the deployed copy.

- **`Settings.Set(key, value)`** validates through the SAME `valid_value` the
  file goes through, so the screen cannot store a value the file would refuse.
  **`Settings.OnChange(fn)`** tells listeners. **`Settings.Flush()`** writes the
  changed keys to the player's file in one pass. **`Settings.Schema()`** exposes
  the schema so the screen can build itself from it.
- **Two rules the file never needed**, because a file is validated as a whole
  while the screen arrives one value at a time: the last personality chance
  above 0 cannot be zeroed (the roll would have nothing to pick), and two
  actions cannot share a key. Both refuse with a reason the screen can show.
- **Persistence is surgical.** `Settings.TextWithValues` replaces the value
  token after `Key =` and nothing else — comments, order, blank lines and the
  player's own spacing survive byte for byte — and the result is read back in an
  empty environment and checked against every expected value before it goes near
  the disk. A file that does not parse is never overwritten; the values stay live
  for the session and the console says so.
  - **A flaw found and fixed by its own tests:** locating the key by
    line-anchoring could not see `return { Pet = 50 }`, which is exactly the
    shape of a hand-written file AND of what our own append path produces. It now
    locates through a mask with comments and string CONTENTS blanked, so a
    mention in a comment (`-- Pet = 999 is too much`) is never mistaken for the
    setting, `KinshipPeach` never matches `KinshipPeachLesser`, and a file it
    cannot read confidently is refused instead of edited.
- **Every module refreshes its own locals from a listener** rather than asking
  Settings at use time, so no hot path gained a call: the assignment updates the
  local every closure already captured. Wired in `Interaction` (all the feed,
  pet, play and peach amounts), `Trust` (PassivePerTick), `Capture` (JoinBonus),
  `Personality` (the seven chances, rewritten IN PLACE in the table the roll
  holds), `Indicator` (ShowPersonalityTags applies now, like the key does).
  `Language` was already live through `Locale.Current`.
- **The keys rebind live, and this is the subtle part.** UE4SS can bind a key
  but cannot UNBIND one, so a rebind cannot take the old key back. Every binding
  instead asks, at the moment it fires, what that key is FOR right now: a key the
  player has moved an action off does nothing. The new key is bound only if it has
  never been bound this session. `Interaction`'s three `RegisterKeyBind` calls
  went through `bind_key(action, name, fn)`; **coopstage2test locates those
  handlers by source text, so its anchors moved with them** (the checks stand).
- **Tests:** `settingstest.js` sections **J** (live changes: validation, the two
  extra rules, listeners including one that throws, no disk write while a slider
  drags, in-place saving that keeps the player's file, every refusal case, a
  broken file left alone) and **K** (the modules follow a change; the old key
  goes inert and the new one works). `localetest`'s Settings stub gained
  `OnChange` — a stub without it is a stub of a module that no longer exists.

### DONE: the controls are on the screen, built from the game's own rows
Applied and tested. **`native_widget(menu, classPath)`** builds any of the game's
blueprints (find the class, `LoadAsset` on demand, `WidgetBlueprintLibrary:Create`
with an owning player — a UserWidget without one does not draw); `native_button`
is now written in terms of it.

**The API the rows are built with, all verified in this build's object dump.**
One native row class covers every shape we need, so the screen does not imitate
the game's Options screen, it IS it:
- `WBP_OptionSettings_ListContent_C` (under
  `/Game/Pal/Blueprint/UI/UserInterface/MainMenu/Option/`)
- `row.BP_PalTextBlock_Name` — the label
- `row:SetSwitcher(bool)` / `row:SetSlider(value, min, max, step, useStep)` /
  `row:SetSelecter_String(labels, index)` — also `SetInteractable`
- read back from `row.WBP_OptionSettings_ListContentSwitch.CurrentIsOn`,
  `...ListContentSlider.CurrentValue`, `...ListContentLR.Current` (0-based)
- the slider's own number is `...ListContentSlider.BP_PalTextBlock_Value`

**The decisions behind it, so none of this is re-derived later.** The whole list
is built from `Settings.Schema()`, so a setting added to the file appears on the
screen with no second place to remember it, and the CONTROL SHAPE is derived from
the entry rather than chosen by hand: `kind` language/key -> a selector, `min 0
max 1` -> a switch, anything else -> a slider.
- **Rows are POLLED every 150 ms while the page is open**, not hooked. The switch
  and the selector have no delegate we could hook without adding three more
  native hooks to the mod; polling runs only while the player is standing in a
  paused menu, the cheapest moment in the game; and one loop that reads every row
  is far less machinery than a hook per control type. The loop carries a token, so
  a page opened again cannot also be polled by an older loop, and it stops on
  close, on supersession and on destruct (all three tested).
- **A refused value is put back into the row.** A screen still showing a number
  the mod did not accept is lying about the state of the game. The reason goes on
  a note line at the bottom, where the player is actually looking.
- **The slider's step follows the range** (1 / 10 / 100): 0..200000 at step 1 is
  200000 positions and unusable. The exact number is drawn beside the slider,
  which is what a player reads anyway.
- **Keys come from a curated list, not "press any key".** Capturing a press means
  binding every key on the keyboard to find out which one was pressed, and taking
  the player's whole keyboard to read one press is what another mod's own notes
  warn against. Anything UE4SS does not know on this build is dropped from the list.
- **ScrollBox and VerticalBox are safe here because they are OURS.** The rule that
  costs crashes is about mutating the GAME's live panels; inside our own subtree a
  reflow is ordinary UMG.
- **One write, on close.** A slider drags through dozens of values and none of
  them touches the disk; closing the page is when the player has finished, and
  they are standing still in a paused menu while it happens.

**A bug menutest H caught before it ever reached the game, worth remembering
because of its SHAPE:** a language and a key have no `min`/`max`, so asking them
for a slider step threw — and because the build loop was unguarded, that one bad
entry took the WHOLE page down, leaving the rows already built dangling and the
player with no screen at all. Fixed twice over: the arithmetic is guarded, and
each row is now built in its own `pcall` so a setting whose shape this code does
not expect costs that one row and nothing else.

**Verified against Dragón's REAL settings file**, not only synthetic ones
(`tools/harness/realfilecheck.js`, and his file is backed up at
`save-backups/PalBonds_settings.before-live-screen.lua`): four values changed, and
the result parses, keeps every other value identical, keeps the same number of
comment lines and the same number of lines overall — nothing reflowed.

**Tests:** `menutest.js` section **H**, 30 checks: a row per schema key and the
sections as headings; the shape derived per entry; rows seeded from the current
values with the slider's range, step and number; the language list offering auto
plus every language and starting on the one in use; the key list offering only
keys UE4SS knows; a drag/switch/selector reaching its setting through the watch;
the chance-zero refusal snapping the row back AND putting the reason on screen;
the watch scheduled only while the page is open and stopped on close and on
destruct; the save happening on close and the value surviving it. The suite's UMG
fake grew the game's row widget (same methods, same read-back fields) plus
SizeBox/ScrollBox/VerticalBox.

**One thing to ask Dragón, not to decide:** the row labels. They are currently
the setting names from the file (`Pet`, `FeedBase`, `ChanceNormal`) because those
are the only names that already exist, they need no translation, and a player who
has edited the file recognises them. Nicer wording is a content decision he has
not made, and inventing it in 17 languages first would be inventing the thing he
asked to decide later.

**Also still open:** nothing is committed or pushed, and the screen has not been
seen in game yet — 24 native rows are built on the first click, which is the one
real risk left (the reference mod's crash family is widget churn inside an open
menu, though its incidents came from pre-building ~100 rows on EVERY ESC open,
automatically; ours builds once, on demand).

### Better Mod Manager (studied 2026-09-25, Dragón subscribed so it could be read)
At `steamapps/workshop/content/1623730/3803996980/`. Credits DarnMenu for the
groundwork, so there is no new hooking technique — but two things are worth
knowing. **It does not touch the ESC menu at all:** it adds a real tab to the
game's main in-game menu (`WBP_InGameMainMenu_C`, `WBP_MainMenu_C`,
`WBP_MainMenu_Tab_C`) and hooks `WBP_PalCommonButtonBase_C`'s `BP_OnClicked` /
`BP_OnHovered` / `BP_OnUnhovered`, which are far cleaner than the ESC row's long
delegate name. That is closer to the "new tab" Dragón originally described, if we
ever want to move. **And it offers mods an optional registration library**
(`modconfig.lua`, loaded from ITS folder, ~15 lines in ours, degrades to nothing
when absent) — a cheap way to appear in its menu later, not a substitute for our
own screen. Its `ui.lua` (15 KB, vs DarnMenu's 200 KB) is the leaner kit to read
for primitives: `T_prt_frame_1px` borders, `WBP_PalInvisibleButton_C` as the
press surface, and a button registry keyed by address + full name (the same
identity rule this project arrived at independently).

## THE IN-GAME SETTINGS SCREEN — milestone 1 built (2026-09-25)

**Dragón's ruling on where it goes:** *"ideally we simply add it to the game
menu the player already knows and uses like the esc menu, and we simply add a
new tab there with the name palbonds mod or something like that - but if that is
not posible then a shortcut key like f7 to open the settings menu would have to
do then"*. The ESC route turned out to be possible, so **F7 is not needed** and
no key is taken from the player.

**And on scope:** *"as for what belongs in it, we can worry about that later,
first we need to see something visible for the player ingame, no point in adding
more values to the settings if we cant even achieve the screen itself"*. So this
milestone is the SHELL only — a row named `PalBonds` and a page with its title
and a Close button. No setting is on it yet, by his instruction. He also chose
the safest placement (bottom of the existing list) and the label `PalBonds`.

**It lives in one new file, `mod/PalBonds/Scripts/Menu.lua`,** initialised last
in `main.lua` inside its own `pcall`. Deliberate: it is the only module that
builds widgets inside a native menu, so it can be dropped from a package without
touching a line of what already ships, and it cannot take the mod down.

### The five rules in that file are crashes somebody already paid for
Do not "simplify" any of them. Each is load-bearing.
1. **Never build inside the `NotifyOnNewObject` callback.** The engine is still
   assembling the menu; mutating it there is `AV writing 0x80`. We wait 50 ms on
   the game thread, which is still inside the open animation, so nothing pops in
   late. (menutest A pins this.)
2. **Only ever add a child to a `CanvasPanel`.** Adding to a `VerticalBox`
   reflows the whole column on the engine's NEXT layout pass — after our Lua has
   returned, so there is nothing left to `pcall`. That is what killed DarnMenu
   three times out of three under ESC-spam, and a plain `AddChild` (no tail
   detach) still reflows, so append-only was never a fix. Our row is therefore
   positioned ABOVE the bottom column on the shared canvas, never inside it.
   (menutest B: the parent is `Canvas_Buttons` and the column gains no children.)
3. **Never `RemoveFromParent` on a menu we no longer own.** A replaced menu
   lingers and keeps painting; touching its children AVs. The engine frees our
   widgets when it destroys the menu, so we simply forget them. (menutest F/G.)
4. **A raw `.Text = "string"` write crashes this game** — our own crash,
   2026-09-04, `Indicator.lua`. Text goes through the game's own
   `BP_PalTextBlock_C` (taken off a live instance on this same menu) and
   `SetText_GDKInternal`, the pair that fixed it. It also means the font and
   colour arrive already matching the menu.
5. **Build the page on the FIRST CLICK, never ahead of time.** Widget churn
   inside an open menu is DarnMenu's crash family: pre-building its page on
   every ESC open caused seven incidents before it was switched off.
   (menutest D.)

### The widget names, all verified against THIS build's object dump
`WBP_MenuESC_C` (the menu) and `WBP_MenuESC_Button_S_C` (its own row
blueprint), plus `Canvas_Buttons`, `Canvas_Content`, `WorldOptionCanvas`,
`CanvasPanel_0`, `VerticalBox_293` and `Text_InviteCode`. Note which of these
are real PROPERTIES on the class (Canvas_Buttons, Canvas_Content, Text_InviteCode)
and which are only reachable through the widget tree (`VerticalBox_293`,
`CanvasPanel_0`) — the lookup tries the property first because that is one
reflection call against the walk's hundreds.

`VerticalBox_293` is the BOTTOM column ("Return to Title"), which is where a mod
row reads as native. The TOP column (`VerticalBox_148`) is auto-sized and reports
height 0, so anchoring under it lands in the middle of the native rows.

The row is created with `WidgetBlueprintLibrary:Create(menu, cls, GetOwningPlayer())`,
NOT `StaticConstructObject` — that is what gives it an owning player. (The older
note under the DarnMenu study says `StaticConstructObject`; the reference's actual
code uses `Create`, and so do we.)

### Sharing the shelf with other menu mods
`Canvas_Buttons` is public space. DarnMenu, **Better Mod Manager** and AntiPhat
all pin a row above the same column and compute the same spot we do, so whoever
injects second draws on top of the first. We read the canvas's bottom-anchored
children (read-only — it mutates nothing, which is what makes it safe on a
native panel) and sit above whatever is already parked there. Learned once and
cached for the session: another mod cannot be installed mid-session.

The stretched slot matters here. The bottom column is anchored (0,1)-(1,1), and a
stretched slot is made of OFFSETS: writing Position/Size into one produces a
rectangle the slot cannot represent and Slate crashed laying it out. Inheriting
the column's Left/Right also matches the native row width for free. (menutest B
asserts the offsets and that no position/size was written.)

### A bug the new suite caught before Dragón ever ran it
Refusing a click whose widget identity does not match ALSO erased the record for
our own genuine button, because a foreign widget on a recycled address shares
that address — so one stray click from another mod's button would have killed our
entry for the rest of the session. The record is now forgotten only when OUR
button is the one that went away. A failed probe is evidence about the probe.

### Tests
**`tools/harness/menutest.js`**, 7 sections, 47 checks: nothing built inside the
construction callback; the row on the canvas above the column with the column's
own offsets; the shared shelf; the page built only on the first click and only
once; only our own buttons act (a native ESC row falls through, a recycled
address is refused, our entry keeps working); ESC pressed twice leaves the older
menu alone; destruct forgets it and the next menu still works. Its UMG fake
reproduces the parts the real crashes came from — a canvas that can REFUSE a
child by returning nothing, and a stretch-anchored slot.

**`tools/harness/runall.sh`** now runs every suite with the right prelude in one
command (`sh runall.sh`, or with a scripts path). Written because a suite given
the wrong prelude ABORTS rather than fails, and an aborted suite reads like a
passing one if you only skim the output. All 25 suites pass against `mod/` and
against the deployed copy; hoistcheck 1 / undefcheck 4 unchanged (the known
false positives). `localetest`'s string-count canary went 25 -> 26 for the one
new translated word.

### Player-facing text
`menu_close` ("Close") added to `Locale.lua` in all 17 languages. The entry
itself reads `PalBonds`, which is the same word everywhere. That is deliberately
the ONLY translated word on the screen so far — anything else added to the page
needs its Locale entry in the same pass, and there is no point translating
placeholder prose that Dragón's content decisions will replace.

### NOT done, and what is next
- **Nothing is committed or pushed.**
- **No setting is on the page yet** — his call, and the next decision to make.
- **The live re-read is still the real prerequisite** (see "Pending"): settings
  are parsed once at load, so a screen that changes a value cannot apply it yet.
  Build that before putting controls on the page, not after.
- **Not verified in game yet.** Deployed to the dev install with
  `DEBUG_LOGGING = true` for Dragón's test run; every claim above is from the
  object dump, the reference implementation and the offline suite, not from a
  screenshot.

## 1.1.8 = THE CLEAN-SHIP PASS (started 2026-09-23)

**Dragón's standing rule, restated after he found disproven mechanisms still
sitting behind `false` switches in a shipped file:** *"when we work on the mod
in dev or local, you're free to activate all logs and whatnots - tries and
tests and old codes [...] but that is ONLY in local and while developing -
WHEN WE SHIP, NOTHING OF THAT MUST REMAIN - no logs, no trash, no extras, no
code that was used just once to check something that's now stale."* From now
on **"let's ship this version" is the whole instruction**: it means produce a
clean package without being told the cleanup part again. Nothing is lost by
deleting -- git history and `docs/hook-points.md` keep the record.

**Done so far (all 24 suites pass after every step, syntax-checked per cut):**
- Combat.lua 4,731 -> 4,431 lines. Deleted: `USE_OLD_MOVE_ORDER_NUDGE`,
  `USE_REPEATED_OTOMO_COMPOSITE` (with `get_or_build_otomo_composite`,
  `OtomoCompositeCache`, `Combat.TickRealOtomoFollow` and its call in
  Trust's tick), `USE_ORBIT_WHEN_AT_GOAL`, `USE_MOVE_TO_ACTOR_FOLLOW`, and the
  whole 165-line native-leash section (`USE_NATIVE_LEASH_FOLLOW`,
  `ensure_leash_for`, `update_leash_anchor`, `release_leash`, the CDO cache and
  the safety counters).
- The `LoopAsync` fallbacks in Trust and Indicator: a path that would only fire
  in an emergency it is not safe for. Both now just log the failure.

**Comments: the package ships NONE of them (Dragón, 2026-09-23).** His
question settled it -- *"why would a player who has no intention to even work
in the mod need to have files with the story of experiments and comments? isn't
that meant for github only?"* So `mod/` keeps every comment (development
source, on GitHub) and `tools/strip-comments.py` builds the shipped trees
without them. The stripper is string-aware: it never touches text inside quotes
or long brackets, so the settings file the player edits keeps its explanations
and messages containing dashes are intact. **18,830 source lines -> 9,748
shipped.** Line numbers in a player's crash report still resolve, because the
stripped tree is committed with each release.

**Diagnostics removed in the same pass** (settled questions, their code deleted
rather than silenced): `dump_follow_action_fields` (15 native reads per follow
install even with logging off), `log_boss_geometry` + `[BOSS-GEOM]` +
`[DIAG-GEOM]` (boss bars confirmed in 1.1.3), Capture's `[EXPERIMENT]`
narration from when the sphere-less capture was one (with `read_owner_id`,
which only fed it), the `[WORKER-BIND-FIX-DIAG]` widget dump and its
`lastLoggedPushedClass`, `[HP-WATCH]` with its `HP_WATCH_VERBOSE` switch, and
`[DAMAGE-WATCH]`. What stays is failure reporting inside live features
(`[DIAG-CREATE]`/`[DIAG-LABEL]` say why a bar or tag failed to build) and the
logging system itself, which is how a player produces a bug report.

### RELEASE GATE — no version ships without these, in order

1. `mod/` is the source of truth; the package is built from it
   (`tools/strip-comments.py`), never edited by hand.
2. All suites pass **against the built release tree**, not only `mod/`.
3. **Dragón runs the exact package in game** and says it works. A green
   harness proves the code behaves the same under stubs; it cannot prove the
   mod loads, that the hooks register, or that anything appears on screen.
   Until that run happens the honest words are "packaged, needs a smoke run".
4. Only then: stores, then GitHub.
5. **The live version's artifacts stay untouched until its replacement is
   actually live** — zip, release trees and tag. While a version is serving
   players it is the rollback and the reference for any bug report about it.
   (Broken once, 2026-09-23: the 1.1.7 zip was deleted while 1.1.7 was the
   live version and 1.1.8 was untested. Restored from git.)

**1.1.8 IS PACKAGED, NOT PUBLISHED:** `release/PalBonds-v1.1.8.zip` (17 files,
101 KB -- 1.1.7's was 339 KB), `Info.json` 1.1.8, both release trees stripped
and identical, all 24 suites pass AGAINST THE RELEASE TREE, syntax checked
after every single cut. The 1.1.7 zip was deleted (it is a GitHub release
asset). Nothing has been committed, pushed or uploaded for 1.1.8.

## MULTIPLAYER IS THE ACTIVE WORK (2026-09-21)

Dragón: make the mod work for co-op, hosted worlds and dedicated servers, by
whatever route works, and ask him for any test that helps -- advance as far as
possible before the two-player session with a friend. The plan (host-
authoritative: the world's owner does every Pal-side job, guests supply input
and show display) and the current test are in `docs/multiplayer-questions.md`,
"THE PLAN", "Net probe run 1" (the private line works both ways), "Stage 1"
(built, and co-op run 1 PASSED: a guest's pets, follow, join and messages all
worked on the dedicated server) and "Stages 2 and 3" (built 2026-09-21,
harness-tested, awaiting co-op run 2: several players per host/server, claims,
dedicated-server detection, the join light and bars/tags for guests via the NEW
`HostView.lua`; release notes for later are listed there). Co-op runs 2 and 3
done (run 3: the whole guest loop works on a dedicated server, combat assist
included); the run 3 fixes (guest-language messages, per-player F10, F8 and
food charging for guests, ask backoff) are built and deployed, awaiting co-op
run 4 -- planned as the single friend session. **Machine state for co-op run 1:** the local
dedicated server has a manual UE4SS (rename its `dwmapi.dll` to remove), the
server net probe, AND PalBonds itself with full logging and a TEST settings file
(`Pet = 125`, delete after); the game's dev copy has `GUEST_INPUT_PROBE = true`
in Session.lua (mod/ ships false) and the client net probe mod in `ue4ss/Mods`.

## Where we stand — read this first (2026-09-15, after the performance work)

**v1.1.2 = the microstutter fix, committed and pushed to GitHub as the new
stable version on Dragón's instruction** (*"lets update all of this to github
as the new stable version - we will have to upload it to nexus and the steam
workshop too, but one step at a time"*). **Then PUBLISHED to both stores the
same afternoon, all verified:**
- **Nexus:** Dragón uploaded `release/PalBonds-v1.1.2.zip` via the Update
  button. The page header reads 1.1.2 (last updated 15 Sep 3:13PM). There is
  one main file, "PalBonds V1.1.2", and the changelog is saved in Dragón's
  wording. That last point was confirmed from his screenshot: the Changelogs
  accordion never renders its entries in the logged-out in-app browser, so
  don't call it empty from there.
- **Steam Workshop:** the same item 3797816321, so no duplicate. The change note
  is dated 15 Sep, and `.workshop.json` now reads `last_published_version`
  1.1.2 with the change note.
- **The game's installed copy updated when Dragón re-ticked the items:**
  `Mods\NativeMods\UE4SS\Mods\PalBonds\` is md5-identical to the release (10
  scripts, profiler OFF), and ManagedMods records Version 1.1.2. The Workshop
  UE4SS loaded PalBonds cleanly (14 hooks, no Lua errors). Dragón's quick run
  on the published build: *"i think it did [feel smoother]"*.

- **What 1.1.2 is:** the two fix rounds in "Known open defects" #0 (PlayerRef,
  hook-fed nameplates and personality scan, sensor cache first, label/bar
  update gating, cache-only regular scan, death/world-exit player tracking,
  controller from the character) plus the dev profiler shipped OFF. Release
  trees and `release/PalBonds-v1.1.2.zip` verified md5-identical to `mod/`
  (10 scripts incl. the new `PlayerRef.lua` and `Profiler.lua` with
  `PROFILING = false`); Workshop `Info.json` Version 1.1.2.
- **Verified in game (runs D, E and an unrecorded run F):** no Lua errors, 14
  hooks, bonding/joining/fights/betrayal/death-respawn all normal. Standing
  still, 1% low 33 fps with the mod vs 36 fps with it off (13–16 before);
  bonding 13 stutters/min vs 91; fighting 19 vs 55. Dragón after run F: *"the
  game feels significantly better and less laggy"*.
- **LESSON — the frame recorder itself caused felt lag.** Run E (recorded,
  with PresentMon's live console stats on) felt laggier than run D (whose
  recording silently failed). Dragón's theory, then his unrecorded run F: *"it
  was the recording itself the one who caused lag, i suspected it because it
  felt constant, not when doing interactions"*. Use PresentMon for numbers,
  never judge FEEL during a recorded run, and keep `--no_console_stats`.
- **Dev install still has `PROFILING = true`** in its `Profiler.lua` (only that
  line differs from `mod/`). It adds a little overhead; set it false there when
  performance work is done.

**v1.1.1 (still what the stores serve)** is v1.1.0 plus exactly ONE confirmed
fix (owned Pals no longer roll a personality and no longer show a tag) — 2
files, 41 lines, nothing else. Everything from the despawn investigation was
reverted rather than shipped; see "KNOWN LIMITATION" below.

- **Nexus:** published 2026-09-14 11:56PM via the file row's **Update** button
  (not "Add file" — see "Publishing procedure" below). Mod version header
  reads 1.1.1, one file listed, 1.1.0 archived, changelog entry saved.
- **Steam Workshop:** published 2026-09-15 00:29 on the same item
  **3797816321** — no duplicate item. Change note: *"Owned Pals no longer roll
  a random personality or show a personality tag - that system is for wild Pals
  only."*
- **Known Issues** (the bonded-Pal despawn) is now stated on BOTH store pages,
  in Dragón's own wording, which is the accurate one — following starts at
  `FOLLOW_TRIGGER_RATIO = 0.5` (`Trust.lua:35`), so "50%+ friendship bar" is
  literal, and "complete the bond" is correct because filling the bar fires the
  sphere-less capture and an owned Pal is no longer spawner-owned.

**URGENT (2026-09-16): v1.1.2 — the SHIPPED version — crashes on a world
change.** Bond a Pal, quit to the menu, load a world →
`EXCEPTION_ACCESS_VIOLATION reading 0x338`. Dragón confirmed it with the
Workshop 1.1.2 copy (vanilla fine, 1.1.1 fine in two runs: pet-only and
feed-only). Cause, from the 1.1.1 log vs the dev log: 1.1.1's fast loop
re-searched for the player every ~4 s, the search came back empty on quit and
`[WORLD-RESET]` dropped every reference; 1.1.2's `PlayerRef.lua` kept returning
the old character (still passing UE4SS IsValid during teardown), so the reset
never ran. The harness reproduces this exactly (`worldchangetest.js`: section C
fails on 1.1.2, passes on 1.1.1).
**Fix (PlayerRef.lua only):** once a second, `UKismetSystemLibrary::IsValid` on
the kept player (engine check, no search); and while a Pal is following, a real
search every 4 s (1.1.1's cadence; never runs with no follower). Both log
`[PLAYER-LIFE]`. **HOTFIX BUILD, in Dragón's game folder for a live test:**
`git show f31b823:release/workshop/PalBonds/Scripts/*.lua` (the exact 1.1.2
release) + `mod/PalBonds/Scripts/PlayerRef.lua` from the working tree, with
`DEBUG_LOGGING` and `PROFILING` on. Today's dev scripts are parked in the game
folder as `ue4ss/Mods/PalBonds/Scripts.dev-2026-09-16`. If the live test holds,
this becomes a 1.1.3 hotfix (ship from 1.1.2 + PlayerRef, logging OFF) before
the boss/Friendly work; do not ship until Dragón confirms in game.
**CONFIRMED 2026-09-16:** several quit/reload runs, no crash; the reset fired
("5 follower(s)"). Cost: ~11 player searches/min at ~39 ms each while a Pal
follows — Dragón: "almost imperceptible... acceptable for now".
**Dragón's call: 1.1.3 = the crash fix PLUS the finished work.** The full dev
tree (`mod/PalBonds/Scripts`, DEBUG_LOGGING + PROFILING on) is in his game
folder as the release candidate. Candidate list given to him: (1) crash fix,
(2) boss tag + bar, (3) failed pets give nothing, (4) no double pay, (5) 3 s
abandon grace — all confirmed live; (6) x2 meter for gym/raid/predator bosses,
(7) humans show Normal and keep their AI, (8) self-defence reach 3000,
(9) 20% brief follow (cat confirmed; no passive gain during it, fixed
2026-09-16) — awaiting the RC run. NOT included: three-boss layout, the
despawn-while-following gap, and the spies (strip before shipping).
**Dragón narrowed it (2026-09-16): 1.1.3 = items 1–7.** Items 8 and 9 wait for
the next update ("once we polish it further"). They stay in the code behind
module switches, both `false` for 1.1.3: `Personality.FRIENDLY_BRIEF_FOLLOW`
(false = the exact 1.1.2 20% behaviour, `legacy_friendly_reset`, plus the
human-NPC guard) and `Combat.SELF_DEFENCE_EXTENDED_REACH` (false = 1800). The
harness tests both states (bosstest G = shipped; B/D switch them on). The dev
copy in his game folder is now the 1.1.3 candidate (`mod/` + DEBUG_LOGGING on,
PROFILING off). He confirmed humans show Normal in the previous run; the last
run checks the boss x2 meter, then GitHub/Nexus/Workshop — build the release
from `mod/` with logging OFF; the spies are diagnostics-gated and silent there.

**v1.1.3 BUILT (2026-09-16), items 1–7, after Dragón's final run** (sleeping
Pal refused, quit/reload with a fed follower fine, boss bars fine, gym Lyleen
bar 250 = x2 and a double pet refused, humans Normal; three bosses at once
still unchecked, too rare). `release/PalBonds/Scripts` and
`release/workshop/PalBonds/Scripts` are byte-identical to `mod/` (10 files,
logging/diagnostics/profiling all false, both held-back switches false),
`release/workshop/PalBonds/Info.json` Version 1.1.3,
`release/PalBonds-v1.1.3.zip` built (same layout as 1.1.2, LICENSE included;
the 1.1.2 zip removed) and the full harness run against the UNZIPPED package.
READMEs updated (bosses x2 wording; crash-fix known-issue entry). Next, one step
at a time as Dragón directs: Nexus (Update button), then Workshop, and GitHub
only when he asks. The dev copy in his game folder still has DEBUG_LOGGING on.
**Nexus 1.1.3 LIVE (2026-09-16 20:31):** header 1.1.3, one main file "PalBonds
V1.1.3" (267 KB), changelog entry in Dragón's one-line-per-change wording.
Workshop upload folder updated to 1.1.3 (10 scripts identical to release,
Info.json Version edited in place, `.workshop.json` untouched — note it still
says last_published_version 1.1.1, so the uploader does NOT write that back).
Local dev copy disabled again (dwmapi.dll / enabled.txt → *.MODS-DISABLED) for
his Workshop test.
**Workshop 1.1.3 PUBLISHED (2026-09-16, `.workshop.json` now says
last_published_version 1.1.3) — BUT the world-change crash STILL happens with
the Workshop install** (0x338 at 20:53:31). The game's copy
(`Mods/NativeMods/UE4SS/Mods/PalBonds/Scripts`) is byte-identical to the
release. Key difference from every successful fix test: the Workshop UE4SS is
a different build (`v3.0.1 Beta, Git SHA 2281fa31`) from the manual one
(`ba2efd55`). Both log "FCallbackGarbageCollector", so that is not it. The
crashed session's UE4SS.log was overwritten by his relaunch 20 s later and the
release writes no mod log. Next: DEBUG_LOGGING + SHOW_DIAGNOSTICS switched on
in the GAME'S Workshop copy (local only, not published) for a logged repro;
he must not relaunch before the logs are read.
**v1.1.3 on GitHub: commit `bd8e0ca` (pushed 2026-09-16). Workshop change note
live (16 SEP 20:46); Steam shows only "Fixed a crash that 1.1.2 introduced" for
the first line — the sentence after the period was dropped.**
**Logged repro (21:01–21:06): NO crash in several tries.** Three quits with a
follower (PinkCat, PlantSlime, and the boss WeaselDragon/Chillet following):
each time `[PLAYER-SPY] search (kept player became invalid)` → `[WORLD-RESET]
the player left the world`. So the fix works on the Workshop UE4SS too; the
20:53 crash is unexplained. Dragón: "im pretty sure all i did was just try to
bond with a boss and then quit and re-join a world", but repeating that didn't
crash; parked until it happens again.
**NEXT SESSION, FIRST TASK — suspect for that crash:** `Indicator.lua`'s
`bossEntries` / `pendingBossGauges` (new in 1.1.3) hold boss-bar widgets and
their `TargetCharacter`, and `Combat.ResetForNewWorld` does NOT clear them
(nor `trackedBars`, the old pass-285 note). The gauge canvas is GameInstance-
lived, so after a world change the 2 s tick can read a widget whose boss is
gone — `Trust.HasBondingState(actor)` / `get_friendship_ratio(actor)` on an
actor that UE4SS may still call valid (it did for the player). Fix: an
`Indicator.ResetForNewWorld()` called from `Combat.ResetForNewWorld`, plus
harness coverage; ship as 1.1.4 once tested. His game's Workshop copy is left
with DEBUG_LOGGING on (SHOW_DIAGNOSTICS off) so a repeat leaves a log.

**NEXT SESSION STARTS HERE (Dragón, 2026-09-15): the boss display update.**
Bosses show neither the trust bar nor the rolled personality tag, because
their HP bar is a different widget from the one Indicator.lua attaches to.
Full notes are in "Next steps" 0b. **2026-09-16: built and deployed to the
dev copy, awaiting its first test run** together with the 20% reset spies
("Next steps" 0c).

**The microstutter report (Workshop commenter *Goldaer*, against 1.1.0) is
RESOLVED in v1.1.2** — reproduced, profiled and fixed on 2026-09-15. The full
record (A/B baseline, profiler, both fix rounds, runs A–F with numbers, and the
remaining minor stalls) is under "Known open defects" #0. Worth telling Goldaer
on the Workshop page once 1.1.2 is published there.

- **GitHub:** `master` is the only branch. **The v1.1.2 commit (2026-09-15) is
  the stable code.** Earlier: `1d06a5a` was the 1.0 stable code, `b10e763` was
  v1.1.1.
- **Steam Workshop:** item **3797816321**, "PalBonds - The Befriending Mod",
  published at 1.1.0. https://steamcommunity.com/sharedfiles/filedetails/?id=3797816321
- **Nexus Mods:** published 2026-09-14. https://www.nexusmods.com/palworld/mods/5623
- **Reddit:** announced in 2 posts.
- **The mod now has real subscribers beyond Dragón.** Anything pushed to
  Steam/Nexus from here on reaches them too — see "Publishing safety" below
  before touching the uploader.
- **Confirmed in live play** (runs 37-39 and the raid-boss test): following,
  combat assist, self-defence, the churn and hit-lag fixes, feed by rarity, the
  alpha x2 bar, the F8 cheer stopping with the Pal, and bonding a raid boss
  without breaking anything.

### Publishing safety — read before touching anything Steam/Nexus-facing

Dragón, 2026-09-14, after seeing changes land in his local Workshop content
folder: *"the idea is that we dont upload things we havent checked yet... we
cant risk something breaking the game for others or causing more problems than
what it fix"*.

- `steamapps\workshop\content\1623730\3797816321\` is a **local folder** on
  Dragón's disk. It is both his subscription (what his game reads when he
  plays the Workshop copy) and the Palworld Mod Uploader's source folder. It
  is completely fine — expected, even — to keep deploying fixes there so
  Dragón can test them in a real session; that is how testing before
  publishing works in this project. **Editing files in it does not reach
  Steam's servers or any other subscriber.** Only running the Mod Uploader
  (which bumps `Version` in `Info.json` and pushes a new version) does that,
  and only that action affects the other subscribers who now exist.
- Never run, or suggest running, the Mod Uploader, `git push` to a shared
  remote treated as a release, or the Nexus upload flow unless Dragón
  explicitly asks for that specific step, separately from "deploy this fix so
  I can test it."
- **One step at a time.** When Dragón names a later step alongside the current
  one ("check the Nexus page, then we do the Steam Workshop"), that is him
  describing the order of work, not authorising the second half. Do the step he
  asked for, report, and stop — including the read-only prep for the next step,
  which from his side looks identical to starting it. He interrupted a turn
  over exactly this on 2026-09-15.

### Publishing procedure — both stores, as actually performed for 1.1.1

**Nexus (mod 5623).** Use the **Update** button on the existing file's row, NOT
"Add file". "Add file" creates an independent second entry and leaves the old
one live; Update links them, archives 1.1.0 (still downloadable under "File
archive"), and — the part that matters — tells everyone who downloaded the old
file, including Vortex and the Nexus app, that an update exists. Fields that
were used: category Main, display name `PalBonds V1.1.1`, file version `1.1.1`,
**tick "update mod version to match"** (this is what bumps the page header;
without it the page keeps advertising the old version), allow mod manager
download, set as primary, plus a changelog entry. The changelog is what Vortex
shows at the update prompt, so it is worth filling in.

**Steam Workshop (item 3797816321).** The uploader's source folder is
`steamapps\workshop\content\1623730\3797816321\`. Publishing means: replace EVERY
script from `release/workshop/PalBonds/Scripts/` (10 since v1.1.2, which added
`PlayerRef.lua` and `Profiler.lua` — copying only the old 8 would ship a build
that fails to load), bump `Version` in `Info.json`, leave `.workshop.json` **untouched**,
then Dragón runs the Palworld Mod Uploader.

- `.workshop.json` holds `publishedfileid` and is the only thing tying the
  local folder to the published item. Preserve it and the uploader updates
  3797816321; lose it and the uploader would publish a DUPLICATE mod page.
  After a successful publish the uploader writes `changenote` and
  `last_published_version` back into it — a cheap way to confirm the push
  landed.
- **Reload the uploader** before publishing if it was open while the files
  changed; it reads `Info.json` at scan time. The version it displays is the
  proof — if it still shows the old number it has stale data, and uploading
  then would push new scripts under the old version.
- Edit `Version` **in place** in the live `Info.json` rather than copying
  `release/workshop/PalBonds/Info.json` over it, so no other field or the file's
  line endings can drift.
- `Info.json`'s `MinRevision` is a floor, not a pin — a Palworld update does not
  require changing it.

**BUG UNDER INVESTIGATION (2026-09-15, found on the published v1.1.2): the
"abandoned" status never triggers.** Dragón bonded a Pal, then ran far away to
see the "left behind" toast, but the bond never broke.

- **His question:** could it be the player-check change made for the
  stutters (PlayerRef)?
- **Code facts:**
  - `EXPERIMENTAL_FOLLOW_NO_TRUST_LOSS = false`, so punishment is not switched
    off.
  - Past `MAX_FOLLOW_DISTANCE` (3000) and not fighting for
    `DRIFT_GRACE_SECONDS` wipes friendship and calls
    `on_follower_lost_all_trust("too far from player")`, which gives the
    "abandoned" toast.
  - **`DRIFT_GRACE_SECONDS` is 3 as of 2026-09-15 (was 15).** Dragón asked
    when the window had appeared: he expected the pre-pass-323 rule, where
    crossing the leash ended the bond instantly unless the Pal was fighting.
    The history shows pass 323 (2026-09-12) added the 15s window after his
    complaint about losing Petallia right after a fight, and that he was only
    consulted on march-vs-warp, not on the window covering ordinary drift. He
    then set it to 3: *"ok, shorten that to 3 seconds"*. A Pal that is
    fighting is still fully protected, with no clock at all.
  - A scratch harness run of the REAL Trust tick with diagnostics on still
    breaks the bond correctly. The logic works offline, so the in-game cause
    is an input.
- **DIAGNOSED from the spy run (log archived at
  `perf-captures/bug-abandon-palbonds-live.log`, 19:20–19:23):**
  - **The player lookup is NOT the cause.** PlayerRef kept the same
    `BP_Player_Female_C` all run (safety-net searches only), and neither Pal
    was ever "fighting".
  - **Pal 1, Ribbuny Botan: abandonment WORKED.** Recalled past 1800, drift
    clock started at 3475, still 10340 units away at 15s. Then "losing all
    trust", `follow stopped: too far from player`, and the bond-lost message
    "Ribbuny Botan was left behind and gave up on you." Whether it appeared on
    screen still needs Dragón's confirmation.
  - **Pal 2, `BP_FlowerRabbit_C`: the bug.** Drift clock started at 4514
    (19:22:23). Its distance then jumped 6402 → 11082 → **261373** with "no
    controller", its last trace was a TRAINER-REASSERT to Destination (0,0), and
    its spy lines stopped at 10.6s of 15s. No break, no toast, and it was still
    counted as a follower at the world reset ("1 follower(s)").
  - **Cause:** the known spawner despawn (see "KNOWN LIMITATION" below)
    removed the actor mid-countdown. `tick_followers` only processes a
    follower inside `if stillValid then` (Trust.lua ~1167–1506) and has **no
    `else`**, so an invalid follower is skipped silently forever. Its State
    entry, and Combat's follower references, linger until the world reset.
- **Fix to decide with Dragón (it changes what the player sees):** when a
  following Pal goes invalid, end the bond cleanly and tell the player.
  Open questions:
  - which message when its drift clock was running (probably the "left
    behind" one);
  - which message when it despawned while following nearby, which the known
    limitation says also happens;
  - whether an invalid Pal's trust should be kept or wiped. Its identity and
    friendship survive the despawn.

  Also clean up Trust State and Combat's `FollowerActors`/`BondingState` for
  it. The spies stay until the fix is verified in game.
- **Spies added (in `mod/`, diagnostics-gated, REMOVE once this is answered):**
  - `[LEASH-SPY]` every 3s per follower, showing distance, pastLeash, fighting
    plus the reason and hate-target name, the drift clock, the player name and
    both positions.
  - `[LEASH-SPY] leash check SKIPPED` when there is no player position.
  - `[PLAYER-SPY]` on every PlayerRef search (with its reason), death,
    respawn and invalidation.
  - `Combat.IsBusyFighting` now also returns the reason and target; its first
    return value is unchanged.
  - All suites pass; the spy paths were checked offline with diagnostics on.

**UPDATE 2026-09-15, after the publish — back in DEV MODE with FULL LOGGING to
chase a bug Dragón found.** He described it only as "not terrible"; the details
were still to come, and he wants the fix ideally in tomorrow's update.

- **Workshop items:** Dragón unticked both in-game. Verified: no
  `ActiveModList` lines, so it is safe for the manual UE4SS to load alone.
- **Dev install re-enabled:** the `dwmapi.dll` and `enabled.txt` renames were
  reversed.
- **The dev copy is v1.1.2 except three switch lines:** `DEBUG_LOGGING = true`
  and `SHOW_DIAGNOSTICS = true` in its `Logger.lua`, and `PROFILING = true` in
  its `Profiler.lua`.
- **Logs:**
  - `Pal\Binaries\Win64\palbonds-live.log`, written in "w" mode, so it is
    overwritten on every launch. Read it before the next launch.
  - `Pal\Binaries\Win64\palbonds-profile.log`.
- **Before any future publish:** switch all three back to false. They are only
  ever changed in the live dev copy; `mod/` and `release/` stay false.

The Workshop-mode snapshot below is how the machine was right after the
publish, before this.

**Dragón's machine at 2026-09-15 15:26 — WORKSHOP MODE on the published v1.1.2:**
- **Both Workshop items are ticked in-game.** `PalModSettings.ini` lists
  `ActiveModList=UE4SSExperimentalPW` and `ActiveModList=PalBonds`.
- **The game's installed copy is v1.1.2.** `Mods\NativeMods\UE4SS\Mods\PalBonds\`
  is md5-identical to `release/workshop/PalBonds/Scripts/` (10 scripts,
  `PROFILING = false`). `Mods\ManagedMods\PalBonds\Info.json` reads Version
  1.1.2. The InstallManifest shows LastInstallTimeUtc 18:25:55 and tracks 11
  files.
  - Re-ticking the items after the upload DID recopy it this time. Before that
    the copy was still 1.1.1, with the two new files missing, so keep checking
    by hash after every publish.
  - The InstallManifest's `LastWorkshopUpdateTimeUtc` still shows the old
    03:29:50 value; the files are what count.
- **The Workshop UE4SS loaded it cleanly at 15:25:57:** 14 hooks, no Lua errors.
- **The uploader folder** `steamapps\workshop\content\1623730\3797816321\`
  holds the same 10 scripts and Version 1.1.2. Its `.workshop.json` reads
  `last_published_version` 1.1.2.
- **The dev install is DISABLED** (`dwmapi.dll.MODS-DISABLED`,
  `enabled.txt.MODS-DISABLED`); its local UE4SS.log is untouched since 15:04.
  - Its `Profiler.lua` still has `PROFILING = true`. Its other 9 scripts match
    v1.1.2.
  - To go back to dev mode, follow the order in the DEV MODE notes below:
    untick both items in-game first, then reverse the two renames.

The DEV MODE notes that follow describe how the machine was during the
performance work.

**Dragón's machine during the performance work, 2026-09-15 11:11 — DEV
MODE, Workshop mods switched off in-game but still subscribed:**
- **Switching between Workshop and dev no longer needs unsubscribing (found and
  verified 2026-09-15).** Palworld's own mod manager keeps its state in
  `Palworld\Mods\PalModSettings.ini` (`bGlobalEnableMod`, one `ActiveModList=`
  line per active mod). Dragón unticked BOTH Workshop items in-game (PalBonds
  and UE4SS Experimental), which emptied `ActiveModList`. The Workshop files
  stay on disk under `Mods\NativeMods\UE4SS\` and `Mods\ManagedMods\`, but the
  game **does not load them while unticked** — proven by
  `Mods\NativeMods\UE4SS\UE4SS.log` keeping its pre-toggle timestamp across
  later launches. With that confirmed, the two manual-install renames were
  reversed (`dwmapi.dll`, `ue4ss\Mods\PalBonds\enabled.txt` restored) and the
  manual stack loaded alone: one UE4SS (`Loading mods from:
  ...\Pal\Binaries\Win64\ue4ss\Mods`), PalBonds initialised, Dragón petted a
  wild Cattiva and it joined, no crash.
  - **To go back to Workshop mode:** close the game, rename `dwmapi.dll` →
    `dwmapi.dll.MODS-DISABLED` and `enabled.txt` → `enabled.txt.MODS-DISABLED`
    FIRST, then tick both items in-game. Never have the local `dwmapi.dll`
    active while the Workshop UE4SS is ticked — two UE4SS loaders crash the game.
  - **The safety check before re-enabling local:** launch once with local still
    disabled and confirm the Workshop `UE4SS.log` timestamp did not change.
  - **The game DOES detect the manual install.** It shows its "mods active"
    warning with only the local UE4SS running, even though the Workshop items
    are off. (An earlier assumption that it could not see a manual install was
    wrong.)
- **The two UE4SS builds differ.** Local/dev: `v3.0.1 Beta #0, Git SHA
  ba2efd55`, GUI console ON in its `UE4SS-settings.ini` — which is why Dragón
  sees a live log window in dev mode. Workshop (what subscribers run): `Git SHA
  2281fa31`, console OFF. **Matters for performance work:** a stutter measured
  on the dev build is not automatically what subscribers get.
- **The copy the game runs in dev mode is `Pal\Binaries\Win64\ue4ss\Mods\PalBonds\`,
  at 1.1.1** — md5-identical to `mod/` on all 8 scripts, `DEBUG_LOGGING` and
  `SHOW_DIAGNOSTICS` both `false` in its `Logger.lua`. The Workshop copy at
  `Mods\NativeMods\UE4SS\Mods\PalBonds\` is also 1.1.1 but dormant. Steam's
  re-download on resubscribe brought it current, which is NOT the usual
  behaviour (see the fourth-copy warning below): normally that copy is written
  once and never re-synced. **Always verify it by hash rather than assuming
  either way.**
- The pre-unsubscribe backup at
  `save-backups/workshop-3797816321-before-unsubscribe-2026-09-14/` is still
  the insurance copy if Steam ever refuses a resubscribe. It contains a
  `.workshop.json` with the real `publishedfileid`, which means the uploader
  folder can be rebuilt **by hand, without resubscribing at all** — worth
  remembering, because resubscribing is what forces the manual install off.
- **The live install now runs the clean v1.1.1 build**, byte-identical to
  `mod/` on all 8 scripts — every diagnostic and experiment from the despawn
  investigation was reverted, and `DEBUG_LOGGING` / `SHOW_DIAGNOSTICS` are
  back to `false` (the shipped configuration). To debug again, set them
  `true` in the live install's `Logger.lua` only; `palbonds-live.log` is
  written to `Pal\Binaries\Win64\palbonds-live.log` (opened in `"w"` mode, so
  it truncates fresh each launch), and **remember that `SHOW_DIAGNOSTICS` is
  a separate switch** — `DEBUG_LOGGING` alone leaves every suppressed tag
  invisible, which cost two test runs this session.
- **Historical, for when Dragón resubscribes to Workshop later for QA:**
  `steamapps\workshop\content\1623730\3797816321\` was both his subscription
  and the uploader's working folder — publishing still means replacing the 8
  scripts there, bumping `Version` in `Info.json`, and uploading with the
  Palworld Mod Uploader. **Found 2026-09-14, still true whenever Workshop is
  subscribed again:** the file the game actually runs while Workshop-
  subscribed is a FOURTH copy, not the Workshop content folder itself —
  Palworld's mod manager copies each subscribed mod once into
  `Palworld\Mods\NativeMods\UE4SS\Mods\<ModName>\` and does not keep it synced
  afterward (confirmed stale a full day after the source was fixed). Any
  future Workshop-based test needs that copy refreshed by hand too, and
  `palbonds-live.log` has always lived at `Pal\Binaries\Win64\palbonds-live.log`
  regardless of which Mods subfolder the script loaded from — never inside a
  Mods folder itself. The folders 3797815819 and 3797816106 next to the real
  item are leftover uploader templates, not real Workshop items — harmless.
- **Save backups (gitignored):** `save-backups/2026-09-12_before-raid-boss-test/`
  (SaveGames plus `SteamCloud_1623730`, every file MD5-verified),
  `save-backups/workshop-3797816321-published-1.0.0/`,
  `save-backups/recreated-workshop-folder-3797816321/`, and
  `save-backups/workshop-3797816321-before-unsubscribe-2026-09-14/`. To
  restore saves: close Palworld, replace the contents of
  `%LOCALAPPDATA%\Pal\Saved\SaveGames\` with the backup's (and
  `Steam\userdata\<account>\1623730\` with `SteamCloud_1623730`), then launch.
  The Global Palbox is the local `GlobalPalStorage.sav` and is included. Real
  Steam and world IDs are deliberately not written in this public file.

**Stable-build flags:** `DEBUG_LOGGING = false` in every tree (to debug, set it
`true` in the live install's `Logger.lua` only), `ACTION_CHANGE_PROBE = false`,
`SHOW_DIAGNOSTICS = false`, `QUIET_RETALIATION_DURING_PLAYER_FIGHT = true`,
`DISCOVER_BATTLE_DURING_PLAYER_FIGHT = true` (runs 35/36 inconclusive, left on).

**Store packaging facts:**
- Workshop Info.json: ModName "PalBonds - The Befriending Mod", PackageName
  PalBonds, Author DragonKaiser, Thumbnail thumbnail.jpg, Tags UE4SS + Gameplay,
  InstallRule Lua `./Scripts`, UE4SS dependency string `"UE4SSExperimentalPW"`.
  No enabled.txt in Workshop packages (Palworld's mod manager handles it).
- Nexus / manual: the `PalBonds/` folder with enabled.txt goes into
  `Pal/Binaries/Win64/ue4ss/Mods/` (manual UE4SS) or
  `Palworld/Mods/NativeMods/UE4SS/Mods/` (Workshop UE4SS).
- Thunderstore needs a different layout (manifest.json, 256x256 icon,
  mod/scripts, mod/enabled.txt, shimloader dependency). Not built.

## Species name mapping

Dragón refers to his own Pals by their in-game species name; the code and
every log line show the internal `CharacterID`/class name instead. Confirmed
mappings so far (from `docs/hook-points-archive.md`'s species-mapping
correction and repeated log cross-references) — **check here before ever
flagging a log's species name as a "mismatch" or "mix-up":**

| Dragón's name | Internal class / CharacterID |
|---|---|
| Petallia | `BP_FlowerDoll_C` (alpha/boss form: `BP_FlowerDoll_BOSS_C`) |
| Tanzee | `BP_Monkey_C` |
| Flopie | `BP_FlowerRabbit_C` |
| Daedream | `BP_DreamDemon_C` |

## What this mod is

Instead of only capturing Pals by force, the player walks up to a wild Pal and
pets, feeds and plays with it. A per-individual trust value rises with good
treatment and slowly while the Pal follows. Cross 20% and its personality turns
friendly; cross 50% and it follows and defends the player; fill the bar and it
joins the party on its own, with no sphere thrown. Hit it yourself, or leave it
too far behind, and you lose it.

Nothing new is authored — no models, textures or animations. Everything reuses
behaviour the game already has.

**Scope:** singleplayer / self-hosted only. Mods on official Pocketpair servers
risk a ban.

**Stack:** UE4SS (Okaetsu's experimental Palworld build, v3.0.1 Beta, Git SHA
`ba2efd55`) with all logic in Lua. The installed build's authoritative Lua API
is the `docs/lua-api/` folder of that exact commit — not memory, not a strings
grep of `UE4SS.dll` (both have produced wrong API names here; see "Retired
approaches").

---

## Current state

v1.1.0 is published (see "Where we stand"). v1.0.0 (commit `abe5ec8`) was the
earlier release; both crash fixes found after it (world change, pass 285;
death/respawn, commit `94adf54`) are in 1.1.0. Confirmed in live play:

- Pet, feed and play on wild Pals through the game's own radial menu, plus F8
  Play, with the player's cheer ending together with the Pal's animation
- Trust bar and personality tag drawn under the wild Pal's health gauge
- Seven personalities rolled per individual, with player-facing names
- Bonded Pals follow, stay *behind* the player, and hold still while aimed at
- Combat assist via the Hate system, and self-defence when a companion is
  attacked outside the player's fight
- Feed trust by food rarity (50 + 10..50); Kinship Peaches keep 250 / 500
- Level-scaled bonding bar; alpha (`BOSS_`) Pals need twice the trust
- Sphere-less joining, with a celebration animation, a join VFX, a named toast,
  and a flat +50000 friendship head start
- Betrayal (player hits the Pal) and bond loss by distance
- F9 personality tags on/off, F10 passive friendship gain on/off

### Owned-Pal tag fix, 2026-09-14 — CONFIRMED, and the only change in v1.1.1

Dragón noticed already-captured Pals were rolling a random personality tier
(and showing its tag) the first time they were summoned as the active Otomo
or placed to work at a base. Root cause: `Personality.GetOrInitState` creates
state for every `PalCharacter` the periodic scan finds via `FindAllOf` —
owned or wild — and only checked monster/NPC status before rolling, never
ownership. Enforcement already refused to ever *write* a rolled tier onto an
owned Pal's real AI (`try_enforce_personality_with_sensor`'s existing
`Capture.IsAlreadyOwned` check), but nothing stopped the roll itself from
being assigned and displayed for a Pal that was already the player's own.

**The fix, both halves:**
1. `Personality.GetOrInitState` checks `Capture.IsAlreadyOwned(palActor)`
   before rolling, in the same "checked before anything else" position as the
   existing monster/NPC exclusion — an owned Pal gets `rolledTier = "normal"`
   unconditionally, same treatment as NPCs/bosses/village NPCs.
2. `Indicator.lua`'s `personality_display_text` checks the same thing first,
   before even the broken-bond label, and returns an empty string for any
   owned Pal — **no tag at all**, per Dragón: *"owned pals should not show
   tags at all, they're already part of the player's roster so they dont need
   any tag."*

**Confirmed live.** Dragón summoned 22 base Pals + 1 Otomo (23 owned) plus
whatever wild Pals were nearby. The log's breakdown: 22 `normal (already
owned)`, 1 `normal (not a confirmed monster)` — together exactly his 23 owned
Pals, all excluded — plus 24 genuinely wild Pals rolling real variety and 11
more landing on `normal` by honest chance (the 35% weight). Then the display
half was confirmed separately: *"now it looks as it should."*

Minor known quirk, not urgent: one Otomo took the "not a confirmed monster"
branch rather than "already owned". Same visible result either way.

**Three process lessons from getting here, all of which cost real test runs:**
1. **A deploy that misses one copy looks exactly like a fix that doesn't
   work.** The first test showed no change because the build never reached
   the copy the game actually runs. See "Deploying a change".
2. **`SHOW_DIAGNOSTICS` is a separate switch from `DEBUG_LOGGING`**, and
   `[PERSONALITY-ROLL]` is in `SUPPRESSED_TAGS` — so the log looked empty
   while the code was running fine. Two more tests were spent concluding "it
   never ran" from a filtered log, against Dragón's direct in-game
   observation. **His direct observation was right; the log was blind.**
3. When a log can't distinguish two explanations (here: "excluded because
   owned" vs "rolled normal by chance"), **fix the log rather than guess** —
   adding the reason to the line is what actually settled it.


### Dev-vs-QA install — Dragón's call, 2026-09-14, adopted

Dragón, after two wasted test cycles in one session: *"felt like we were much
better before working entirely on local... working with the mod subscribed is
useful to check what the other players are seeing, but that should be QA, not
our DEV."* Correct, and now backed by concrete evidence from the same session:

- The Workshop-subscribed setup has (at least) two copies to keep in sync —
  the subscription/uploader folder AND the separate native-mods copy Palworld
  actually runs — versus one copy for a manual install. Missing the second
  one silently produced "the fix didn't work" instead of "the fix never ran,"
  costing a full test cycle before it was even noticed.
- `DEBUG_LOGGING = false` is correct for the stable/shipped build, but it also
  means `palbonds-live.log` — the fast, direct diagnostic this project has
  relied on since its first session — writes nothing at all. Confirming
  anything now requires reading UE4SS's own log instead
  (`Palworld\Mods\NativeMods\UE4SS\UE4SS.log`, or
  `Pal\Binaries\Win64\ue4ss\UE4SS.log` for a manual install), which mixes
  engine noise with mod output and has none of `Logger.lua`'s own filtering.
- A manual install lets `DEBUG_LOGGING` be flipped `true` in exactly one file,
  in Dragón's own dwmapi-toggled copy, with zero effect on what any subscriber
  sees — the same isolation the "Publishing safety" section above already
  established for local edits, just applied to the *manual* copy instead of
  the Workshop one.

**Going forward: active development uses the manual install; the Workshop
subscription is for periodic QA only** — confirming what real subscribers
experience on a build about to be published, not day-to-day iteration. To
switch back to manual for a dev session: re-enable
`Pal\Binaries\Win64\dwmapi.dll` and
`ue4ss\Mods\PalBonds\enabled.txt` (reverse the `.MODS-DISABLED` rename), and
make sure the Workshop-based UE4SS ("UE4SS Experimental", 3625223587) is not
also active at the same time — **never both**, the game crashes when two
UE4SS copies load. Exact toggle mechanics for disabling a subscribed Workshop
mod without unsubscribing are Dragón's own call/action in Palworld's in-game
mod list; not yet exercised this session.

### Cleanup pass, 2026-09-11

An external audit (a different AI, without this project's context) returned a
cleaned tree. It was verified rather than trusted, and the result is now
deployed to `mod/`, `release/PalBonds/` and the live game install:

- Shipping code went from 6,230 to 4,763 real code lines. All of it was dead
  research code; every functional hook survived (14 of them), and every
  hard-won fix survived byte-for-byte, including the pass-285 GameInstance
  outer fix.
- **It shipped two real defects, both fixed here.** `WORKER_MENU_OVERLAY_CLASS`
  was used but its declaration deleted — an undeclared Lua local reads as a nil
  global, so `Interaction.Init()` threw, and `Trust`/`Combat`/`Capture` never
  initialised at all (9 hooks instead of 57). And `update_territory_anchor` was
  called after its definition was deleted, throwing silently on every follow
  tick inside `safe_call`.
- Two genuine improvements were adopted from it: `[FOLLOW-RESTORE]` (detect via
  `HasAction` that the follow action is no longer installed and rebuild it —
  more precise than only rebuilding when the Lua object goes invalid), and
  moving `ApplyCompanionPreset` above the `GetHateSystem()` early return so
  preset restore no longer depends on the hate system being readable.

**Lesson worth keeping:** the break was invisible to reading and would have been
invisible in game (the mod loads, prints nothing alarming, and simply does
nothing). It was caught by *running* the code. See "Verifying a change" below.

---

## Where things live

```
32-PalBonds/
  CLAUDE.md            <- this file: current state, rules, next steps
  CLAUDE-archive.md    <- full narrative history (Continuación 1-180)
  DESIGN.md            <- the design: subsystems, phases, research questions
  README.md            <- repo readme (GitHub-facing)
  mod/PalBonds/        <- dev tree, mirrors what ships
  release/PalBonds/    <- release staging (same Scripts as mod/)
  release/README.txt   <- the readme that ships to players
  release/workshop-description.txt  <- Workshop description as saved (live page edited later by Dragón)
  release/nexus-description.txt     <- Nexus description (BBCode)
  release/PalBonds-v1.1.0.zip       <- Nexus / manual-install package
  release/workshop/PalBonds/        <- Workshop package mirror (Info.json, thumbnail.jpg, Scripts)
  save-backups/        <- real save data and Workshop folder backups (gitignored)
  images/              <- Steam Workshop screenshots
  docs/hook-points.md  <- technical pass-by-pass log (the real detail)
  docs/hook-points-archive.md
  stale/               <- archived, not part of the product (gitignored)
```

`mod/PalBonds/Scripts/` and `release/PalBonds/Scripts/` are kept identical, and
both are kept identical to the live game install. There are exactly 8 modules:
`main`, `Logger`, `Personality`, `Interaction`, `Trust`, `Combat`, `Capture`,
`Indicator`.

**Live game install:**
`C:\Program Files (x86)\Steam\steamapps\common\Palworld\Pal\Binaries\Win64\ue4ss\Mods\PalBonds\`

---

`tools/harness/` — the offline fengari test harness (see its own README, and
the section on it further down). Its `node_modules/` is gitignored; restore with
`npm install fengari`.

`stale/` — gitignored local archive: the five third-party reference mods, the
FModel mapping data, the pre-release dev-install backup, and retired research
modules. Nothing in it is part of the product, but the reference mods are worth
re-reading before building anything new (see the design rule about existing
implementations).

## Working procedures

### Deploying a change

Copy the changed `.lua` to **every** location listed under "Where we stand"'s
"Dragón's machine right now" note — dev tree, release staging, the manual live
install, the Workshop content folder, AND (2026-09-14 on) the Workshop native
mods copy (`Palworld\Mods\NativeMods\UE4SS\Mods\PalBonds\Scripts\`), which is
the one Dragón's actual play session runs while manual install stays disabled
— and confirm with `md5sum` that all of them match. A change that is only in
`mod/` has not been tested by anyone; a change that reaches everywhere except
the native-mods copy tests nothing either, and looks exactly like "the fix
didn't work" instead of "the fix never ran" — this already cost one full test
cycle.

### Shipping a release — the full checklist

Added 2026-09-27 because Claude handed Dragón a changelog and no short
description, and he had to point out it was missing: *"you forgot to give me the
short description, seems you've either not checked your mds for this or you
never added it to your work process"*. It is in the work process now.

1. `mod/` clean: every ship switch off (`DEBUG_LOGGING`, `SHOW_DIAGNOSTICS`,
   `TRACE_PHASES`, `ACTION_CHANGE_PROBE`, `PROFILING`), no temporary flags, no
   diagnostic-only files.
2. `python tools/strip-comments.py mod/PalBonds/Scripts release/PalBonds/Scripts`,
   then copy those same files to `release/workshop/PalBonds/Scripts` and confirm
   the two trees are md5-identical.
3. Bump `release/workshop/PalBonds/Info.json` `"Version"`.
4. `sh tools/harness/runall.sh release/PalBonds/Scripts` — a stripped build is a
   build nobody has tested.
5. Zip with **forward-slash entry names**. PowerShell's `Compress-Archive`
   writes backslashes; build it with Python's `zipfile` instead.
6. **Two pieces of text, both needed, both Dragón's to approve:**
   - a **changelog**, ONE LINE PER ITEM, prefixed `New:` / `Balance:` / `Fixed`;
   - a **short description**, one or two sentences, the blurb that sits on the
     file entry.
   Draft both, never claim more than has been measured, and never promise fixes
   or dates (see the memory on public text).
7. Nothing is uploaded, committed or pushed without him saying so, per store.

### Verifying a change — do this before asking Dragón to test

There is no Lua interpreter on this machine, but `fengari` (a Lua 5.3 VM in
JavaScript) runs under Node and is enough to catch load-time breakage:

```bash
npm install fengari
node harness.js <path-to-Scripts> prelude.lua
```

`prelude.lua` stubs the UE4SS globals (`RegisterHook`, `FindFirstOf`,
`ExecuteInGameThreadWithDelay`, `UEHelpers`, …) as no-ops returning nil, then
the harness `dofile`s the real `main.lua`. What it proves:

- whether `main.lua` completes or aborts, and on which line
- how many hooks register — **the healthy number is 14**; a lower number means
  init died partway and everything after it never ran

It cannot prove gameplay behaviour, since every game call returns nil. It
catches exactly the class of bug that reading misses. The working copies live in
the session scratchpad; rebuild them if they are gone, it is worth it.

### Turning mods off (Dragón joins community servers)

Any active mod is a ban risk there. Rename, in
`Palworld\Pal\Binaries\Win64\`: `dwmapi.dll` → `dwmapi.dll.MODS-DISABLED`.
That single file is UE4SS's proxy DLL, so without it no Lua mod runs at all.
Reverse the rename to re-enable. Check separately that
`Pal/Content/Paks/LogicMods/` and `~mods/` are empty and that no other proxy DLL
(`xinput1_3`, `d3d11`, `version`, `winmm`, `dinput8`, `bink2w64`) is present.
Client-side cleanliness is verifiable; a third-party server's own policy is not.

---

## Decisions that are settled — do not re-litigate

- **Pet and Feed are radial-menu interactions, not keys.** F9/F10 as Pet/Feed
  were removed deliberately. Play keeps F8 only because it has no radial-menu
  equivalent yet.
- **Grumpy and Hostile stay separate personalities.** Dragón: *"while grumpy
  doesnt attack inmediately, it can attack if it sees another pal of its same
  species attacking, so kind of like they join - its an interesting
  personality"*. Do not merge them as a tidy-up.
- **No fallbacks that hide failure** while the project is in development. A
  failed read shows "unknown", never a plausible-looking default. This came from
  a real bug where a "friendly" fallback made most Pals look friendly.
- **Read everything you need from a Pal BEFORE `PalCaptureSuccess` runs.** The
  actor is torn down during capture and every component read fails afterwards.
  This bug has been introduced twice; resolve names and handles up front and
  pass them along as plain values.
- **`ActionComponent:ActionIsEmpty()` is not a reliable "is busy" signal.** It
  reports empty in the gaps between steps of a real multi-part interaction.
  Three separate attempts to detect "the animation finished" failed on it; the
  capture delay is now a fixed 5s on purpose.
- **A low-level Pal bonding in a single interaction is intended, not a bug.**
  Dragón, 2026-09-11: *"yes the level difference allowed to bond with just 1
  interaction thats on purpose to somewhat match high level catch on low level
  pals"* — it mirrors how trivially a high-level player captures a low-level
  Pal normally. A lv30 Pal against a lv61 player gets a 125-point bar, and one
  75-point feed clears 50% of it. Do not "fix" this.
- **Never propose removing a working feature to work around a bug.** Fix it, or
  ship with the limitation documented.
- **Feed trust scales with item rarity; Kinship Peaches are the exception.**
  Feed = 50 base (same as Pet and Play) + 10/20/30/40/50 for rarity 0-4
  (common..legendary), confirmed in run 38 (Carrot/Berries = 0, uncommon = 1).
  Kinship Peaches keep 250 (lesser) / 500 (full). Dragón, 2026-09-12: *"lets
  keep the kinship peaches special values, differently than other food, they
  cannot be cooked or made, only found out, so it makes sense that those peaches
  are special things"*.

## Two routes to "the right brain" — Dragón has ruled on both (2026-09-12)

Pass 325 found that `UPalOtomoHolderComponent::ActivatePalByHandle` spawns a Pal
as a real active Otomo, with `BP_MonsterAIController_Otomo_C`, using only the
game's own systems (proven by the Multi Party Pals Summons reference mod). That
gave two possible ways to stop fighting the wild AI:

**1. Capture the Pal earlier — REJECTED, do not propose again.** Summoning a
bonded Pal as an extra Otomo requires it to be in the party, so it would mean
capturing at the moment following starts instead of at full trust. Dragón's
ruling: *"i honestly dont like it, because it would shorten the bond with the
player we would be losing betrayal, passive friendship gain, the toasts, etc -
too many things just for one, so that consider it a no go."* The bonding phase
is the product; trading it for better pathing is the wrong trade.

**2. Possess the wild Pal with an Otomo controller — held in reserve.** Not
rejected, but explicitly not the current plan: *"lets leave it as a risky option
if what you're currently doing doesnt work and we have to try other things - if
your method works, then that settles it and we wont even need to try that."* So
this is only on the table if the action-pushing approach stops improving. Do not
open it while the current method is still gaining ground.

---

## Retired approaches — do not resurrect

Each of these was killed by evidence, not suspicion:

- **Territory / leash following** (`SetupLeash`) — an inner radius tight enough
  to hold followers also caged them, so they could not reach an attacker and
  stopped defending themselves. Also leaked leash actors.
- **The repeated Otomo composite** (`SetRootComposite` + `SetOtomoFollowAction`)
  — reported success every time and moved nobody.
- **`ABP_ReturnPalEffect_C` as the join VFX** — correlates only with switching
  active Otomo, never with a capture. The real VFX was found later.
- **`SelectedFeedingItem` called cold** — caused a crash that left the game
  running but unresponsive.
- **`OpenOtomoFeedInventory()` to open the picker directly** — needs a real
  deployed Otomo, so a new player could never feed, never bond, never get a
  first Pal.
- **Guessing UE4SS API names.** `RegisterInitGameStatePostHook` is real;
  `…PostCallback` is not. Four wrong names cost four test cycles. Read the api
  docs at the installed commit.
- **Subtracting hate to steer a target.** Run 25's `[HATE-VERIFY]` logged the
  player still most-hated *immediately after* `ChangeHate(-999999)`. Every fix
  built on it was a no-op: `clear_player_hate`, `PLAYER_OUTBID_HATE`,
  `Trust.ClearMutualHate`, `enforce_companion_truce`, `release_assist_hate` and
  the original hate-based recall. Adding hate still works and is what
  `[HATE-ASSIST]` uses.
- **`TargetActor` and `SetTargetAndNextAction` on the running combat action.**
  Both are declared on `UPalAIActionCombatBase`, and neither resolves on
  `BP_AIAction_CombatPal_C` in this build. `SetTargetAndNextAction` failed 29
  times out of 29 in run 27 with *"attempt to call a TrivialObject value"*, and
  `TargetActor` read as unreadable every time. Recorded once already in pass 217
  and repeated in pass 322 — **check `docs/hook-points.md` before reaching for
  this class again.** Use `UPalHate::FindMostHateTarget()` instead; it works.
- **UE4SS's async Lua** (`LoopAsync`) — a UE4SS collaborator states plainly it
  is unsafe. Dead fallbacks using it still exist in `Trust.lua` and
  `Indicator.lua`; see open defects.

---

## Combat assist and following — where they stand (runs 37-39, 2026-09-12)

**Working and confirmed live.** Dragón after run 37: *"the pals behaved
nicely"*; after run 38: *"it was a lot better this time, wasnt as laggy during
fights"*; run 39 and the raid-boss test: nothing broke.

What made the difference (details in `docs/hook-points.md`):
- **The recall-vs-assist loop.** Companions are not sent after an enemy further
  than `COMBAT_RECALL_DISTANCE` (1800) from the player, nor while their own
  recall is running. It had cost up to 68 follow rebuilds and 140 combat
  installs in one fight. `reachtest.js`.
- **Follow starvation.** The global follow-install limit is deleted; it lost
  five Pals in run 36. Per-Pal install caps are 60s rolling rates.
  `captest.js`.
- **Hit lag.** The damage hooks looked the player up with a full `FindAllOf`
  walk on every hit (41 walks per 30-hit burst). Now cached, at most 2.
  `hitcosttest.js`.
- **Self-defence.** `Combat.OnFollowerAttacked`: a companion hit outside a
  player fight fights back, only that Pal (Dragón's call).
  `selfdefencetest.js`.

Still true, not blockers:
- **Friendly fire.** With 4-6 companions, 5-20 companion-on-companion hits per
  fight; target discipline ends the duels. The runs 35/36 A/B on
  `DISCOVER_BATTLE_DURING_PLAYER_FIGHT` was inconclusive (two versus six
  companions), so both switches stay on. Any future A/B must use an in-session
  toggle rather than two separate runs, because spawns cannot be controlled.
- **Remaining hook cost.** Run 38 measured ~4.7 ms per damage event inside the
  two damage hooks, including one-off fight assignment. The measuring wrapper
  (`timed_hook` / `[HIT-COST]`) was removed for the stable build; bring it back
  from commit history if lag returns.
- The follow and combat actions still share priority slot 10, so some install
  churn per fight is inherent.

---

## The offline test harness — use it, it has paid for itself

`tools/harness/` holds a fengari-based harness that runs the **real mod source**
with the UE4SS globals stubbed. `tools/harness/README.md` has the full command
list. Short version:

```bash
cd tools/harness && npm install fengari
node syntaxcheck.js ../../mod/PalBonds/Scripts
node assisttest.js  ../../mod/PalBonds/Scripts prelude_323.lua
```

It cannot prove in-game behaviour. It has still caught bugs no test run could
have distinguished from "it didn't work again":

- a loop early-out that disabled the recall for exactly the Pal that needed it
- a recall measuring distance from the aim camera, so a failed camera read
  silently switched it off
- a call placed ~850 lines above its definition (a nil global, swallowed silently)
- the pass-331 damage gate that switched combat assist off completely

**The rule: a regression test must be run against the broken code too.** A test
that passes both before and after a fix proves nothing. Every bug-driven suite
in there was verified by reverting the fix in a throwaway copy and confirming the
test fails. Do the same for the next one.

## Never budget a retry from mod load

**Third instance, and it cost a Pal (run 29, 2026-09-12).** `FOLLOW_ACTION_MAX_TOTAL = 40`
counted follow-action installs from mod load and never reset. It ran out
mid-session; `followActionDisabled` latched true; from that second on, no Pal
could ever be given a follow action again. A Flopie then wandered off with
nothing installed to hold her and was lost while Dragón stood still watching.

It survived the earlier cleanup of this exact bug shape because it did not look
like a retry budget — it is a *leak guard*. **The rule covers both.** Any
counter that latches something off permanently, for any reason, is wrong unless
the thing it guards is genuinely unrecoverable. Leak guards should be rolling
rates (N per window, recovers when the window turns over), never lifetime
allowances. Check `FOLLOW_ACTION_MAX_PER_PAL`, `TRAINER_REASSERT_MAX_TOTAL` and
anything else shaped like them before adding another.


**Mod load happens on the title screen.** A Blueprint hook (`/Game/...`) cannot
be registered until that class is actually loaded, which does not happen until
the player is in a world — and that can be ten minutes later on a slow load.
A native hook (`/Script/...`) registers immediately and is never affected, which
is why personality enforcement keeps working while nameplates and the radial
menu quietly do not.

Any bounded retry anchored at mod load is therefore measuring the wrong thing.
This has now cost two separate test runs:

- **Nameplates/trust bars** (pass 297): a 30-round window. On 2026-09-11 the
  hook needed round **136**.
- **The radial menu** (pass 301): a 60-round, five-minute window. On the same
  day Dragón's world did not exist until 9.5 minutes in, so it gave up four and
  a half minutes before there was anything to hook, and he could not pet or feed
  anything for the whole session — *"i could no longer interact with the pals,
  no matter how close i got"*.

Both were invisible, because both logged under suppressed tags. Both now retry
at a slow cadence until they succeed, and report under the non-suppressed
`[TAGS]` / `[HOOKS]` prefixes.

**The lesson that generalises:** the first fix was applied to one instance
without checking for siblings, and the sibling broke a run a few days later. If
a bug class is found, grep for the rest of the class before calling it fixed —
`MAX_[A-Z_]*(ROUNDS|ATTEMPTS)` is the search that finds these.

## Lua errors do NOT appear in palbonds-live.log

A Lua runtime error is caught by UE4SS and printed to **its own console window**,
in red, as `Error: [Lua::call_function] lua_pcall returned LUA_ERRRUN => ...`.
It never reaches `palbonds-live.log`, because that file only contains what
`Logger.log` writes — and a function that threw never got to its log line.

This cost a real diagnosis on 2026-09-12: Dragón reported red lines, the mod log
was grepped for `error`/`FAILED`/`nil value`, nothing was found, and he was told
there were no errors. There was one, and it was serious — `close_combat_window`
calling `pal_has_own_fight` before its definition, killing the entire
combat-window close path. **When he reports red console lines, ask for the
console text; do not refute it from the mod log.**

## Diagnostics: the log filter hides more than you expect

`Logger.lua` has `SHOW_DIAGNOSTICS = false` and a `SUPPRESSED_TAGS` list, and
`Logger.log` **silently drops** any message matching it — everything starting
`[DIAG`, plus `[FOLLOW-DIAG]`, `[RADIAL-WATCH]`, `[TRAINER-REASSERT]`,
`[AIM-FREEZE]` and a couple of dozen more. Turning `DEBUG_LOGGING` on does
**not** bring these back; `SHOW_DIAGNOSTICS` is a separate switch.

This cost real time: the intermittent "personality tags missing" bug logged its
own cause on both the success and failure paths, and every one of those lines
was being thrown away before reaching the file, so a working session and a
broken one produced byte-identical logs. **When a log cannot explain something
it clearly should have logged, check this filter before theorising.** Anything
that must survive the filter needs a tag that is not on that list — the tag
bind-hook lines now use `[TAGS]` for exactly this reason.

## Curiosity, and a player answer we will need: Auri cannot be bonded (2026-09-20)

Dragón asked why Auri — the blue-haired NPC with the `Hablar` prompt, standing
near a boss tower — is completely unaffected by the mod. She is popular enough
that players will eventually ask us the same thing, so the answer is recorded
here rather than re-derived later.

**She is not a character.** Identified with UE4SS's own `DumpAllActors`
(`Ctrl + Numpad 7`, bound in `ue4ss/Mods/Keybinds/Scripts/main.lua`) while
standing next to her — she appeared 138 units from the player as:

```
/Game/Pal/Blueprint/FlowGraph/TalkableLevelObject/SkyBoss/
    BP_PalTalkableLevelObject_SkyBoss.BP_PalTalkableLevelObject_SkyBoss_C
```

Her full chain, read from `ue4ss/CXXHeaderDump`:

```
BP_PalTalkableLevelObject_SkyBoss_C
  -> BP_TalkableLevelObjectBase_Modify_C
    -> APalLevelObject_Talkable
      -> APalLevelObjectActor
        -> AActor
```

She never touches `ACharacter`, let alone `APalCharacter`. In the game's own
terms she is a *level object* — the same family as a warp point or a relic —
that happens to carry a person-shaped mesh. Her internal name is `SkyBoss`
because the asset is named after the encounter she belongs to, not after her;
siblings in the same folder are `BP_PalTalkableLevelObject_GrassBoss01` and
`BP_PalTalkableLevelObject_StrongOldMan001_Release`, one greeter per tower.

Her base class carries only: `UPalSkeletalMeshComponent CharacterMesh` (the
body), `UPalInteractableSphereComponentNative` (the `Hablar` prompt),
`UPalNPCTalkFlowComponent` (dialogue), `UPalLookAtComponent` + a single
`IdleAnimation` montage (she turns her head and loops), and
`UPalLimitVolumeBoxComponent` (you cannot walk through her). There is no
capsule, no movement component, no HP, no AI controller and no
`UPalIndividualCharacterHandle`. She also has `VisibilityCondition` /
`OnQuestStateChanged` / `SetHiddenAndDisableCollision` wired to the quest
manager, so she blinks in and out of existence, collision included, as a prop
does.

That single fact explains every symptom Dragón observed: no name plate, no HP
bar, and capture spheres passing straight through her. It also explains the
mod's silence — `find_targeted_pal` builds its candidate list from
`FindAllOf("PalCharacter")` with no filtering afterwards, so she is never a
candidate to reject. Ten F8 presses from two metres away all logged
`not looking at any Pal`, with no rejection line anywhere, because the mod
cannot perceive her at all.

**Why we will not "fix" this.** Every pillar of PalBonds hangs off the
individual character handle she does not have: trust is stored per stable
individual ID, personality reads the AI sensor's response preset, the trust bar
attaches under a `BP_PalNPCHPGauge` widget, and capture calls
`PalCaptureSuccess` on the handle. For her, all four point at nothing.
Supporting her would not extend the mod; it would be a second mod sharing the
folder.

**The short answer for players:** Auri is not a Pal or an NPC in the game's
code — she is a scripted part of the scenery with dialogue attached, with no
health, no stats and no capture target, which is also why Pal Spheres pass
through her. PalBonds only works on things the game itself treats as Pals, so
there is nothing there for it to bond with.

## Known open defects

0. **Microstutters — FIXED in v1.1.2, CLOSED.** Confirmed as the mod's doing on
   2026-09-15 (Goldaer's Workshop report), measured with PresentMon, fixed over
   two rounds of work, and re-measured: idle with the mod on came back to within
   noise of the mod turned off, and every repeating stall series tied to one of
   our timers disappeared. The full investigation — every capture, every profile
   run C to E, the fix rounds and the numbers — is archived in
   `CLAUDE-archive.md` under "Performance investigation 2026-09-15". The rules it
   bought are still live and still apply: hook-driven over timed world sweeps,
   world searches are what stall a frame, and a rare safety net rather than a
   periodic sweep. What is still measurable is listed as defect 6 below.
1. **Bonded Pals despawn when the player travels far from where they were
   bonded.** A KNOWN LIMITATION, not a task. Investigated exhaustively on
   2026-09-14; the mechanism is understood and the dead ends are recorded under
   "KNOWN LIMITATION: bonded wild Pals despawn when you travel far" below.
   Dragón restated the ruling on 2026-09-28: *"unless something completely new
   arises, there's no goal here ... there's no real way to fix it without
   breaking the flow of the mod"* — which is why it is stated openly in the
   store descriptions instead. Do not reopen it with the old ideas, and do not
   re-run the experiments listed there as dead ends.
2. ~~Singleplayer only~~ **— NO LONGER TRUE as of 1.1.7 (2026-09-23):** co-op
   and dedicated servers are supported and shipped. What is untested is listed
   under "1.1.7 BUILT AND READY TO PUBLISH". Official servers still do not
   allow mods.
3. **`LoopAsync` fallback still present** — re-counted against the code on
   2026-09-28: **one**, in `Combat.lua`. Trust's five and Indicator's one are
   gone (the 2026-09-23 count in this list was stale for five days). Dead code
   that would only run in the emergency it is unsafe for.
4. **World-change references never cleared:** partly fixed. `Indicator` and
   `Interaction` both have a `ResetForNewWorld` since 1.1.4 (tracked bars,
   boss entries, `pendingWildFeedTarget`, the radial caches). What is still
   never cleared is the `SpawnedOtomo` field PalBonds writes into the
   GameInstance-lived radial widget.
5. **`FindFirstOf` exposure** (UE4SS issue #1328): re-counted 2026-09-23,
   `Capture.lua` has 0 and `Interaction.lua` 1
   `FindFirstOf("PalPlayerCharacter")`. None is per hit.
6. **`find_targeted_pal`'s world sweep costs 40-80 ms** while the radial menu
   is open (42-47 ms in 2026-09-15's measurement, 76-78 ms in run 3b's). Read
   the cost correctly: the sweep is already cached one-in-four
   (`PAL_SCAN_CACHE_MAX_AGE = 4`), so it is paid about once every two seconds of
   held-open menu, not per call — the geometry re-runs every call and is cheap.
   It is still the largest named cost left, in singleplayer and co-op alike.
   The untried route (proposed 2026-09-28, not yet Dragón's call): take the
   candidate list from `Personality.ForEachKnownPal`, which the sense hook
   already fills for free, and keep `FindAllOf("PalCharacter")` as a rare safety
   net and as the fallback when that set yields nothing — the same hook-fed
   pattern that removed the nameplate sweep and the personality scan in 1.1.2.
   The aiming maths, the ranges and the menu itself would not change at all.
7. ~~No settings screen~~ **— SHIPPED in 1.1.9 (2026-09-27).** An in-game
   screen under ESC changes every setting live, including rebinding the three
   hotkeys to any key. Kept here only so this number is not read as open.
8. **Friendly fire** is contained, not prevented (see the combat section).
9. **Hotkeys fire while typing in chat** — declined by Dragón 2026-09-14 as
   not worth fixing (see Pending).
10. **Numpad keys and Space cannot be bound** in the settings screen:
   `Settings.resolve_key_name` bridges the game's FKey names to UE4SS's by
   squashing punctuation, which does not cover every spelling. Dragón judged the
   Space case not worth fixing (2026-09-26); numpad breaks the same way. Every
   other key works, and the screen says so rather than failing silently.

**Closed, listed here because they were carried as open for too long:** the boss
defeat record (solved run 9 on 2026-09-19, shipped in 1.1.6), the stuck
waiting pose (fixed run 7, closed 2026-09-28), Esaeon's crash (their UE4SS
build), Swordfish's crash (once, rare, 1.1.5-era, never again), and the three
gameplay hotkeys on `RegisterKeyBind` (never reproduced by anyone — see
"Next steps").

---

## Pending, deliberately deferred

**HISTORY, NOT A TASK LIST.** Everything below is the dated record of how player
reports, design rulings and investigations were handled. Several entries here
describe problems that have since shipped fixes. Rulings and design decisions in
it are still binding; STATUS in it is not. For what is open, read "Next steps".


**SETTINGS ARE READ ONCE AT LOAD (noted 2026-09-23, Dragón asked).** The
settings file is parsed when the mod loads and most modules copy the values
into locals at that moment (`Interaction.lua`'s keys and gains, `Trust.lua`'s
passive tick, `Capture.lua`'s join bonus), so editing the file mid-session
changes nothing until the game restarts. F9 and F10 are the only live
switches, and they are session-only. A live re-read (poll the file, or reload
on demand, and have modules ask `Settings.Get` at use time) is the
prerequisite for the in-game settings screen -- do it first, not after.
**BUILT 2026-09-25** -- see "SETTINGS SCREEN — milestone 2". Editing the FILE
still needs a restart to be noticed; what is live is a change made through
`Settings.Set`, which is how the in-game screen changes one.


**New player report (2026-09-21): Hakaishin Beerus, crash with other mods, plays
co-op.** Posted in Toxik's Steam thread. Report copied to
`docs/bug-reports/hakaishin-0921-rentry.md`. `EXCEPTION_ACCESS_VIOLATION reading
0x0`, VCRUNTIME140 memcpy under UE4SS frames, the same stack hash twice, one of
those with Pal Insight fully removed, so Pal Insight is not shown to be the cause
(Dragón's first read was an HP-bar overlap). Two open leads, NEITHER assumed:
(a) the guest-join fatal crash from `docs/multiplayer-questions.md` if they were
a guest (note: that one is a `LowLevelFatalError` assert, a different signature);
(b) the UE4SS build, since the signature matches Esaeon's `c838a8ac` crash --
but Dragón ruled that Toxik's crash is NOT assumed to be Esaeon's, so ask, don't
diagnose. PalBonds strings "in crash memory" prove nothing (loaded script text is
always in memory). Reply drafted asking: singleplayer/host/guest, what they were
doing, the UE4SS Git SHA, and a PalBonds-only run -- the same triage as Esaeon.

**THEY ANSWERED (2026-09-21, Steam Workshop): it is the known UE4SS build.**
Singleplayer, feeding a Pal, PalBonds alone with every other mod unsubscribed
and its leftover folders deleted, on **UE4SS Git SHA `c838a8ac`** -- the same
15 July build behind every one of Esaeon's crashes, which updating to Okaetsu's
`2281fa31` fixed with no PalBonds change. They also ask whether we can ship an
"older UE4SS compatibility patch", because a newer loader breaks other DLL mods
they use and will not update for. Technical answer for a reply: PalBonds is Lua
only and the faulting frames are inside UE4SS's own native code, so nothing in
this mod can patch it; and the build we point at is Okaetsu's Palworld-specific
one (what the Workshop dependency installs), not the main UE4SS line their DLL
mods broke on, so that exact build is worth trying. What goes in the reply is
Dragón's call.

**AND THAT ANSWER DID NOT HOLD (2026-09-22, their reply).** Two corrections
from them, both of which kill the "it is the old build" conclusion above:
1. They have **only ever used the Palworld UE4SS** (Okaetsu's line), never the
   mainline one — so the premise that a newer mainline loader broke their DLL
   mods was ours, not theirs.
2. They have already tested **`2281fa31` (3 Sept), and it crashes equally**.
   "Trust me, tested it a bunch."
So this is an OPEN crash report on the build we recommend, not a solved one,
and nothing in the Esaeon finding explains it. They also point out that other
Palworld mod authors ship old-UE4SS compatibility patches (DynamicPals on
Nexus, 2 days ago), and that a large group of players deliberately stay on
older builds — Okaetsu's own advice to them was to pick one and stay there.
They were explicit that they are not demanding anything.
**What would actually move this:** the trace build already sitting in
`release/test-build/` (`PalBonds-v1.1.6-test2.zip`, DEBUG + `TRACE_PHASES` on,
`docs/crash-testing-guide.md` written for it) writes one line before every job
it starts, so the last line in the log names the job that was running when the
game died. Publishing it to them is Dragón's call, as `test1` was for Esaeon.
Until that log exists, we cannot say whether a compatibility patch is even a
thing on our side; do not promise one, and do not repeat "update your UE4SS".
**DRAGÓN'S RULING (2026-09-23): wait for them to open the issue and move on.**
"We have already recommended him to do so at least twice already - if he still
fails to do so, we simply continue forward, we cant stop a whole proyect for 1
person." Note the trace build is ALREADY public if they ever want it: GitHub
pre-release `v1.1.6-test2`, with `crash-testing-guide.md` attached.

**New player reports (2026-09-19, after 1.1.5 shipped — not yet triaged by Dragón):**
- **CRASH AROUND THE JOIN, two independent reports.** Esaeon (Proton,
  GitHub issue #1, log saved at `docs/bug-reports/esaeon-issue1-palbonds-live.log`,
  1.1.4, DEBUG on, Pet/Feed only — no F8) ends EXACTLY at the join: join
  toast shown, StopFollowing, ForgetBonding at 19:15:17, then nothing. Not yet
  confirmed with him that the game crashed at that moment. His Nexus comment:
  also crashes "after a while of simply running around", most reliably after
  Pet/Feed; many other mods (PalSchema + 10 schema mods, LogicMods/~mods paks).
  Swordfish (Steam, no other mods): crashed "right when the trust bar went full"
  while spamming Pet on hostile Pals; rare. Lead, unverified: after a join the
  wild actor is destroyed, but only Trust (ForgetBonding) and Combat
  (StopFollowing) drop it; Indicator and Personality still hold references to
  it (a one-actor version of the world-change teardown fixed in 1.1.3/1.1.4).
  A stale reference touched after garbage collection could crash at a random
  later moment, which would also fit "while running around".
- **Feed on a charging Pal (Goldaer, Reindrix):** the Pal ran at him, hit him
  (damage), ran off without eating, and the PLAYER stayed stuck in the
  clapping/waiting animation (could move/jump inside it) until he fed again
  up close.
- **Boss joins don't count (Goldaer):** bonding with an overworld boss did not
  count it as defeated or captured (boss defeat record / Paldeck).
- **Alpha Mammorest falls through the floor after petting** — now a second
  report (Swordfish, twice, uneven terrain). Earlier judged base-game, but
  petting wild Pals only exists through our mod.
- **Feature request (Swordfish):** a way to release Pals back into the wild.
- **ANSWERED AND CLOSED, verified 2026-09-23 (do not re-list these as open):**
  - GitHub issue #1 (Esaeon) is **CLOSED** on the repo. Dragón's instruction at
    the time: close it so nobody reading the repo thinks the project is stuck
    on it or abandoned.
  - The 17 Sep design feedback (ralanost, Warframe666: cooldown feel, no
    indicator, favourite food, bonding through fighting, no distance limit)
    was **answered by Dragón on Nexus, 18 Sep 4:23PM**. His answer is the
    design ruling: bonding takes time on purpose and scales with level (a Pal
    at or above your level takes much longer, a much lower one needs 2-3
    interactions, a Kinship Peach can be enough); there is NO cooldown in the
    mod -- the options hide while the Pal finishes a base-game animation or
    when you are not aimed at it; and you do not wait around, because a Pal at
    50% follows you and keeps bonding while you farm or build.
  - Mammorest through the floor: answered 18 Sep as a base-game clipping issue
    that the pet/feed alignment makes more visible.
- **Icon (Meail):** use the meme image as the Workshop icon. Dragón's call.
- **DRAGÓN'S TRIAGE (2026-09-19):**
  - Crash: do NOT treat the two reports as one bug yet. Swordfish said it was
    rare and hasn't reported again (likely an older version). Esaeon may be a
    conflict with one of their many mods. Next step is information: ask Esaeon to
    confirm the timing and to run 1.1.5 with ONLY PalBonds active (rules out
    Proton vs mod conflict), with both logs. Asked on Nexus 2026-09-19.
    GitHub issue #1: answer (and close) only once it's fixed and finished,
    not before (Dragón).
  - Feed on an attacking Pal: his read is that the Pal's attack lands and
    staggers the player, interrupting the interaction but not the player's
    animation. Fix: stop the player's animation (or reject the interaction)
    when it fails, OR interrupt the Pal so the interaction takes priority. TO DO.
  - Boss joins must count as defeated/captured: find how the game records it.
    TO DO.
  - Mammorest under the floor: base-game limitation, NOT ours. Lifting the Pal
    would only cover uneven ground, not cliffs or walls. Reply as usual.
  - Releasing Pals: backlog, after the settings screen and multiplayer.
  - **Feed fix direction (Dragón, 2026-09-19):** release the player's
    animation when the interaction fails, and a failed feed should cost
    nothing ("stop the interaction entirely"). Finding: for wild Pals the
    GAME never takes the food; our RequestUseToCharacter post-hook takes it
    and grants the trust at the moment the food is PICKED, before the Pal
    walks over. So we can defer both until the Pal actually eats.
  - **Instrumentation for one combined test run (2026-09-19):**
    `Scripts/DevWatch.lua` (TEMPORARY, remove before any release, plus the
    call sites marked "DevWatch" in Interaction, Capture, main and
    `Logger.DebugEnabled`). [PAIR-WATCH] logs player / Pal AI / Pal action
    changes for 15 s after each Pet/Feed, plus the moment the food is taken.
    [BOSS-WATCH] hooks `APalNPCSpawnerBase:ProcessBossDefeatInfo_ServerInternal`
    (header-dump candidate for the boss-defeat record) and lists spawners near
    every joining Pal. [RECORD-WATCH] diffs the player's UPalPlayerRecordData
    (boss defeats, NormalBossDefeatFlag keys, capture counts) every 15 s and
    3 s after a join. 18 hooks with it. For the run, the game's settings file
    has **Pet = 20000** (instant join for the boss): SET IT BACK TO 50 after.
  - **Run 1 results (2026-09-19, 14:56-15:10):**
    - Feed sequence (7 feeds): player `BP_ActionPairStandby_FeedItem` (waiting
      pose) while Pal AI `BP_AIActionPairCall_FeedItem` walks over; food taken
      (RequestUseToCharacter) at ARRIVAL, when the player switches to
      `BP_ActionPairBehavior_FeedItem`; both end together ~5.5 s later. So an
      interrupted approach never costs food (my earlier "taken when picked"
      was wrong). A Lamball that rolled into Dragón and ragdolled left him in
      the waiting pose 6 s, then the game released him itself; no food taken.
      Dragón could NOT reproduce the stuck pose (tried hostile Pals, Reindrix,
      hitting them himself): rarer than thought.
    - Bosses: killing a Menasting fired
      `ProcessBossDefeatInfo_ServerInternal(boss, "sakura_red_B_BOSS")` and the
      record gained that NormalBossDefeatFlag (map: defeated). A PETTED Lyleen
      fired the SAME function during our capture ("sakura_purple_D_LilyQueen")
      but NO flag was written (map: undefeated); it did count as a capture
      (LilyQueen 5 -> 6). Difference: nobody attacked the Lyleen.
    - Dragón: the first defeat gives a key item; a befriended boss must not
      get it twice.
  - **Built after run 1 (tests pass, deployed):**
    - Stuck-pose watchdog (Interaction, `[PAIR-RELEASE]`): after every wild
      Pet/Feed, if the player is in a `BP_ActionPair*` pose and the Pal is out
      of its `AIActionPairCall` for 1.5 s (or gone), or waiting > 12 s /
      eating > 15 s, the pose is cancelled (CancelAction, as for Play's cheer).
      Nothing else is ever cancelled. Test: `pairwatchtest.js` A-H.
    - Boss credit (Capture, `[BOSS-CREDIT]`): for a `_BOSS/_GYM/_RAID` class,
      right before the capture the player is written in as the boss's last
      attacker (DamageReactionComponent.LastAttackerInstanceID from the
      player's IndividualHandle.ID, and LastDeadInfo.LastAttacker), so the
      game's own defeat function credits the player and handles first-time
      rewards itself. UNVERIFIED: run 2 decides. Test: `pairwatchtest.js` I.
  - **Run 2 results (2026-09-19, 15:27-15:34):** the boss credit RAN (both
    fields written and read back as the player) and ProcessBossDefeatInfo
    fired for the right spawner (Lyleen Noct, "sakura_purple_D_LilyQueen_Dark"),
    but still NO defeat flag: the last attacker is NOT the lever. Map:
    undefeated. A petted, already-beaten Mammorest gave no second reward (but
    nothing is written for bosses at all yet, so that proves nothing). Feeds and
    pets all played out normally, no [PAIR-RELEASE] (the watchdog never cut a
    normal one). Pet follows the same pattern: `BP_ActionPairStandby_Petting`
    -> `BP_ActionPairBehavior_Petting`, Pal AI `BP_AIActionPairCall_Petting`.
    The stuck pose still didn't happen.
  - Next: DevWatch now also hooks 9 record-writing candidates
    (PalPlayerRecordDataUtility SetRecordData_*, CaptureJudgeObject
    OnCaptureSuccess, the boss-reward client RPCs, OnDefeatCharacter delegate)
    to see who writes the flag on a REAL defeat or sphere capture. The
    BOSS-CREDIT code is kept for now but is disproven: delete it once the real
    lever is found.
  - **Run 3 (2026-09-19, 15:43-15:46):** Dragón confirmed a sphere-caught boss
    counts as defeated in the base game, then caught an undefeated Grintale
    (NaughtyCat, "81_1_grass_FBOSS_18"). ONLY ProcessBossDefeatInfo fired (none
    of the 7 hookable candidates; the two reward client RPCs couldn't be
    hooked), and the record gained the flag (defeats 8 -> 9). So that function
    decides alone, from the boss's state.
  - **Built after run 3 (tests pass, deployed):** the last-attacker write is
    DELETED (disproven). Replaced by a hate push: for a boss only, right before
    the capture, `Controller:GetHateSystem():ChangeHate(player, 1000)`, so the
    player is in the boss's UPalHate.HateMap the way any fight or sphere catch
    leaves them. Positive ChangeHate is proven in this build (combat assist);
    subtraction is not. `[BOSS-CREDIT]` logs the most-hated before/after.
    UNVERIFIED: run 4 decides.
  - **Run 4 (2026-09-19, 15:52-15:54): hate DISPROVEN too.** Petted an
    undefeated Grizzbolt-line alpha (GrassPanda_Electric,
    "81_1_grass_FBOSS_26"): the push worked (most hated nil -> the player) and
    ProcessBossDefeatInfo fired for the right spawner, still NO flag (captures
    +1, paldeck +1). The hate push is DELETED (Capture has no boss-credit code
    now; pairwatchtest section I removed with it).
  - Ruled out as the lever: last attacker (both fields), the hate table. Not
    visible from Lua: what ProcessBossDefeatInfo checks internally. Unhooked
    lead: `APalCharacter:OnCaptured(SelfCharacter, Attacker)` delegate (what a
    sphere catch broadcasts vs what PalCaptureSuccess broadcasts). Every
    experiment costs Dragón an UNDEFEATED alpha (they respawn only slowly), so
    ask before the next one. Dragón keeps one already-beaten alpha for the
    later "no second reward" check.
  - Dragón: "lets do more runs" (waiting for respawns is fine). Run 5 setup:
    DevWatch `[BOSS-STATE]` snapshot of the boss AT ProcessBossDefeatInfo (both
    cases) and "before our capture" (joins): battle mode, captured-processing,
    dead/dying/live, otomo flags, owner UId, HP, last attacker, dead type,
    most hated. Hooks on `PalCharacter:OnCaptured`, its delegate, and
    `OnDeadCharacter` log who the capture names as attacker. Protocol: one
    sphere catch AND one petted join of undefeated alphas, then diff.
  - **Run 5 (2026-09-19, 16:05-16:08):** sphere-caught Dumud (LazyCatfish,
    "81_1_grass_FBOSS_27", flag written) vs petted Nitewing (HawkBird,
    "81_1_grass_FBOSS_22", no flag). Boss state AT ProcessBossDefeatInfo was
    identical (no battle mode, not dead/dying, no owner yet, no last attacker)
    EXCEPT `IsCapturedProcessing` true (sphere) vs false (ours), and a most-hated
    target (sphere only; hate alone already disproven). OnCaptured and its
    delegate did not fire (native). ALSO: Dragón got stuck in the PET pose on
    the Nitewing: it accepted the pet mid-attack 6-7 m away, the game ended the
    player's pair action at +2.7 s (the Pal went back to attacking), but the
    POSE ANIMATION kept playing until he petted his own Pal. The watchdog only
    looks at the action, so it saw nothing. And the pet was PAID at 0.26 s
    (the Pal's pair call counts as accepting, not arriving): 20000 points, so the
    boss joined without ever being petted.
  - **Built after run 5 (tests pass, deployed):**
    - Boss: `Capture.MarkBossAsBeingCaptured`: for a boss only,
      `CharacterParameterComponent:SetIsCapturedProcessing(true)` (field write as
      fallback) right before the capture, as a sphere does. UNVERIFIED: run 6.
    - Pose: when a pair ends before the shared animation (failed), or the
      watchdog releases it, any montage still on the player is stopped
      (`Mesh:GetAnimInstance():GetCurrentActiveMontage()` + `Montage_Stop(0.25)`),
      logging its name. A pair that ended normally is never touched.
    - Pet pays only once the player is in `BP_ActionPairBehavior_*` (really
      petting); if the player's action is unreadable, the old rule applies.
      Tests: pairwatchtest I-L, bosstest C5.
  - **Run 6 (2026-09-19, 16:25-16:32):**
    - Boss (Foxparks Cryst, Kitsunebi_Ice, "81_1_grass_FBOSS_15"): at the
      defeat routine it had IsCapturedProcessing=true AND the player as most
      hated, i.e. both run-5 differences matched the sphere case, and STILL no
      flag. The boss's state is NOT the lever: the defeat record is written by
      the sphere's (and the kill's) own native code, which Lua can't reach or
      see. The captured-flag code is DELETED. Petted-but-unflagged bosses in
      Dragón's save: sakura_purple_D_LilyQueen, sakura_purple_D_LilyQueen_Dark,
      81_1_grass_FBOSS_26, 81_1_grass_FBOSS_22, 81_1_grass_FBOSS_15.
      Remaining route (needs Dragón's decision): write the record ourselves
      and handle the first-defeat reward ourselves.
    - Stuck pet, reproduced on a Nitewing: the release fired 2 s in and
      stopped `AM_Player_Female_Petting_Middle_Beckon` (the waiting wave, used
      by Pet AND Feed), but Dragón stayed stuck until he rolled. It also once
      stopped `AM_Player_Female_hit`. The pet check correctly refused to pay
      ("accepted the pet but never reached you").
  - **Built after run 6 (tests pass, deployed):** the release only touches a
    waiting pose (Petting/Feed/Beckon in the montage name), stops it with no
    blend, re-checks 0.4 s later, and if it is still playing and the player has
    no action, gives the player a fresh action the way a roll does (the Play
    cheer emote via ActionComponent:PlayAction, cancelled 0.15 s later), logging
    every step. pairwatchtest L-M.
  - **BOSS DEFEAT: STILL OPEN (Dragón, 2026-09-19).** First he said "ideally
    we would let the game itself mark them as defeated and give the items, if
    we do it ourselves, there are too many risks"; I wrongly recorded that as a
    known limitation and he corrected it: "i said 'ideally' not that we flag
    it as a known limitation, if we have to do it manually and give the item
    and mark it as defeated ourselves then we find how to - but IDEALLY we let
    the game itself do it - dont mark stuff as known limitations unless i
    state it myself". So: the game's route stays preferred; if it cannot be
    reached, write the record AND give the first-defeat rewards ourselves.
    What a first kill gives (Dragón, Elphidran, 2026-09-19): technology
    points, a "first boss kill" toast in the centre of the screen, and a
    bounty token. Boss instrumentation was removed from DevWatch (re-add what
    the next step needs); Pet restored to 50 in the game's settings file.
  - **Run 7 (2026-09-19, 17:09-17:14):** a Nitewing pet: the release stopped
    the pose and it was gone 0.4 s later (worked). A Nitewing FEED where the
    Pal HIT him: the top animation was `AM_Player_Female_hit`, left alone
    correctly, but the release then gave up and the waiting pose came back
    underneath: stuck until he rolled. Fixed: another animation on top is
    waited out (re-checked every 0.4 s, up to 6 checks), then the pose is
    stopped; a fresh action (cheer start+cancel) if the stop doesn't hold.
    pairwatchtest N. Dragón also petted an undefeated alpha (Petallia,
    VioletFairy, "81_1_forest_FBOSS_1"): captured, not defeated, as expected.
  - **Esaeon's crash, new evidence (2026-09-19, GitHub #1 comment + Nexus):**
    1.1.5, EVERY other mod disabled (their UE4SS.log: PalSchema disabled, only
    UE4SS's default Lua mods). Crash 5-15 s after a Lamball joined;
    CrashContext: EXCEPTION_ACCESS_VIOLATION reading 0x0, every frame in UE4SS
    (+ VCRUNTIME140 memcpy). palbonds-live.log's last line: [PRESET-SLOTS]
    Warlike, 10 s after the join ([ENFORCE] lines are filtered, so what ran
    after it is invisible). Their UE4SS.log is in UTC ("local disabled due to
    wine") and not flushed per line, so its tail is stale. Their Claude's
    analysis: apply_forced_preset never validated the sensor. Files saved in
    `docs/bug-reports/esaeon-0919-*`.
  - **Built for it (tests pass, deployed, NOT yet verified by Esaeon):**
    - Join cleanup: `Personality.ForgetJoinedPal(palId, actorKey)` (state,
      sensor caches, pawn, handled addresses, sensor index),
      `Indicator.ForgetJoinedPal(palId, actorAddr)` (tracked bars, boss
      entries, pending boss gauges; entries now store `actorAddr`), and
      `Interaction.ForgetJoinedPal(actorAddr)` (radial-menu targets, pending
      feed, the pose watchdog), all called by Capture after ForgetBonding with
      the id/address read BEFORE the capture. `[JOIN-CLEANUP]` logs the count.
      Before this, Personality kept the dead wild Pal up to 10 min.
    - Esaeon's suggestion: `sensor_alive(sensor)` checked at the top of
      apply_forced_preset, and right before BOTH `sensor.AIResponsePreset =
      fresh` writes (ApplyCompanionPreset too).
    - Test: `jointest.js` J1-J5 (22 suites now).
  - **Esaeon test build (Dragón's idea, 2026-09-19):** give them the fix early
    through GitHub instead of making them wait for 1.1.6, so a miss costs no
    release. Built locally, NOT pushed yet (ask first):
    `release/test-build/PalBonds-v1.1.6-test1.zip` = current `mod/` minus
    DevWatch.lua (its call sites are pcall-guarded no-ops), DEBUG_LOGGING ON so
    their log is written without edits, 1.1.5 README. 17 hooks, all suites pass
    against it. `[ENFORCE]` is no longer filtered from the log (it is what ran
    after his last visible line). Plan: commit to a branch (not master, which
    is the 1.1.5 stable), GitHub pre-release `v1.1.6-test1` with the zip.
  - **PUBLISHED 2026-09-19 (Dragón's go-ahead):** branch `test/join-cleanup`
    (commit `f8fb794`; `master` stays the 1.1.5 stable), GitHub pre-release
    https://github.com/DragonKaiser55555/palbonds/releases/tag/v1.1.6-test1
    with `PalBonds-v1.1.6-test1.zip`. Dragón replies to Esaeon (Nexus and the
    issue) with the link. Esaeon's pronouns are unknown: use they/them.
    Local work continues on the branch.
  - Boss reward popup: `UPalNetworkPlayerComponent:ShowBossDefeatRewardUI_ToClient
    (FPalUIBossDefeatRewardDisplayData{TechnologyPoint, DefeatCharacterID},
    AfterTeleport, DelayTime)` and `ShowDefeatBossBonusExpReward_ToClient(int)`:
    run 3 hooked them on the wrong class (PalPlayerController), which is why
    they "could not hook". Client RPCs go through ProcessEvent, so hooked on
    the right class they should show what a real first kill hands out. The
    popup is the RESULT of the server writing the record, not its cause.
  - **Boss Tier Drops (Workshop 3782109509, subscribed 2026-09-19):** PalSchema
    DATA only (AlphaBossDrops.json / PredatorBossDrops.json rewriting
    DT_PalDropItem rows for BOSS_*). No code, no hooks, nothing about the
    defeat record. It does separate the two things a kill gives: drop-table
    items (every kill) and the first-kill bonus (technology points + bonus EXP,
    what the popup reports).
  - **Run 8 setup (built, deployed, awaiting Dragón):** save backed up and
    MD5-verified first (`save-backups/2026-09-19_before-boss-record-write/`,
    SaveGames 462 files + SteamCloud 27). DevWatch `[BOSS-WRITE]`: 25 s after
    a world loads, if `81_1_grass_FBOSS_22` (the Nitewing he petted) is not in
    the record, it calls
    `UPalPlayerRecordDataUtility:SetRecordData_Bool_ForServer(player,
    rec.NormalBossDefeatFlag, FName(key), true)` once, with the whole flag list
    logged before and after. Five other petted-but-unrecorded bosses are kept
    for later tests. Also `[BOSS-REWARD]`: the reward RPCs hooked on the right
    class (UPalNetworkPlayerComponent) to see what a real first kill gives.
    19 hooks in dev.
  - **RUN 8 SOLVED THE BOSS PROBLEM — Dragón found it (2026-09-19).**
    - The direct write is IMPOSSIBLE: UE4SS refuses to pass the record array to
      SetRecordData_Bool_ForServer ("Tried storing reference to a Lua table for
      an 'Out' parameter ... no table was on the stack"). Route closed.
    - His own experiment: he fired ONE bullet at an undefeated boss (Caprity
      Noct / BerryGoat_Dark) before bonding. When it joined through the mod,
      the game recorded the defeat and paid the first-kill reward
      ([BOSS-REWARD]: TechnologyPoint=1, bonus EXP 6060 — the same shape as his
      real Tarantriss kill: 1 point, 5682). The next boss (Gumoss / PlantSlime),
      petted only, produced nothing. So the lever is REAL DAMAGE BY THE PLAYER,
      recorded by the game itself; last attacker and hate were the wrong knobs.
    - **Fix built (tests pass, deployed):** for a boss only, right before the
      capture, `DamageReactionComponent:ForceDamageDelegateForCaptureBall(player)`
      — the game's own "a capture sphere landed" registration: an attacker, no
      damage. The game then writes the record and pays the reward itself, so a
      boss already beaten gets nothing twice and we write nothing into the save.
      `Capture.RegisterPlayerHitOnBoss`, logged as [BOSS-CREDIT].
    - That event comes back through our own damage hook, so
      `Trust.OnFollowerDamaged` now returns early when `st.captureTriggered` —
      otherwise the mod would punish the player for its own capture (half the
      bar and a "trust is shaken" toast mid-join). Tests: pairwatchtest O,
      pointstest P5.
    - The [BOSS-WRITE] test code in DevWatch is now pointless: remove it
      (keep [BOSS-REWARD], it reads the result).
  - **RUN 9: BOSS DEFEAT VERIFIED WORKING (2026-09-19).** Broncherry
    (SakuraSaurus), bonded with NO shot fired: [BOSS-CREDIT] ok, then the game
    paid the first-kill reward by itself ([BOSS-REWARD] TechnologyPoint=1,
    bonus EXP 6195) and the map marked it defeated. In the same run a Chillet
    (WeaselDragon) he had ALREADY beaten: [BOSS-CREDIT] ok, and NO reward
    fired — the game refuses the second payout on its own, which is exactly
    Dragón's "must not give the key item twice". No betrayal/shaken lines: the
    captureTriggered guard holds. Both joins dropped 8 leftover references.
  - **Esaeon, test build 1 result (2026-09-20, GitHub #1): STILL CRASHES, and
    the join is NOT the trigger.** Crash 139 s in, seconds after the THIRD pet
    on a Chikipi, no join in the whole session (logs saved as
    `docs/bug-reports/esaeon-0920-*`). The crash stack is IDENTICAL to the
    first one, all 64 frames, VCRUNTIME memcpy + UE4SS only, reading 0x0 -- so
    both crashes hit the same place inside UE4SS from different call sites.
    (`PCallStackHash` is the SHA-1 of an empty string in both dumps, i.e. the
    field is unused; their AI read it as "byte-for-byte identical".)
    Their AI blamed Combat's 5 s [POST-BOND-DUMP]: its silence is not evidence
    (that tag has been filtered from the log since the 1.1.2 cleanup), and the
    timing clears it -- it fired at 19:07:44 and the log kept going to
    19:07:53. DELETED anyway (2026-09-20): dead diagnostic, six native reads on
    a possibly-dead action object, exactly the risky shape.
  - Dragón finished all 16 translated Workshop descriptions (Russian and
    Thai were rewritten shorter: Steam's character limit).
  - Icon: no (the meme isn't square).

**New player reports (Nexus posts, read 2026-09-18):**
- **Esae0n (18 Sep):** plays through **Proton** (Linux / Steam Deck
  compatibility layer). Taming works, but the game crashes *every time*
  immediately after a Pal joins. Possibly the keybind-thread bug fixed in pass
  333 — a join destroys the wild actor and builds the party one, a small
  version of the world-change teardown — but only if they used F8 Play. If
  they used only Pet/Feed, it is something else and Proton is a real suspect.
  Dragón was given a reply draft asking which interactions they used and for
  their UE4SS.log. Ask them to confirm once 1.1.4 is out.
- **Warframe666 (17 Sep):** the alpha **Mammorest** in the starting area
  sometimes **falls through the floor after being petted**. New, not
  investigated.
- Design feedback worth keeping (ralanost, Warframe666, 17 Sep): bonding feels
  like waiting on cooldowns; no indicator for when Pet/Feed is available again;
  ideas — favourite food, bonding through fighting together, no distance limit
  so you can bond while doing other things. Dragón has not ruled on any of it.

**1.1.4 RELEASED (2026-09-18) — Nexus, Steam Workshop (change note live,
`last_published_version` 1.1.4) and GitHub (`8846dca`).** Dragón smoke-tested
the exact release files locally AND the Workshop copy before uploading. Still
open from this release: the Proton player's reply (Dragón posted it), the
Nexus/Workshop description line about forgiveness — **Dragón: not needed**, "too
small of an addition and one that should've been there from earlier, since
that's what 'friendly' would make you think" — and the disabled-old-mechanisms
cleanup (next update).
- **Mod-compatibility questions (CS-Eden on Steam asked about "Random Sized Pals",
  2026-09-18):** Dragón does not test other mods. Answer from what we know
  overlaps. Aiming uses `GetScaledCapsuleRadius/HalfHeight`, so resized Pals are
  accounted for; the only foreseeable issue is the known small interaction
  area on very large Pals. Say "should work, untested, tell us", and never
  claim compatibility outright.
  - **Random Sized Pals (makkhan, Workshop 3789632682) — code read 2026-09-18,
    compatible.** It has one hook,
    `PalCharacterParameterComponent:OnInitializedCharacter`, and two frames
    later (game thread, `ExecuteInGameThreadAfterFrames`) it changes the
    MESH's `DefaultScale3D`/`RelativeScale3D` plus
    `static.MeshCapsuleHalfHeight/Radius`, keyed per individual ID. It skips
    bosses, and has no keybinds and no AI or trust changes. It does NOT resize
    the root collision capsule our aim reads, so an enlarged Pal keeps its normal
    interaction area inside a bigger model: aim at the middle of the body.
    PalBonds never hooks spawning (personalities roll when a Pal is first
    noticed) and writes the sensor's preset, which is a different component.
    Dragón subscribed only to let Claude read it; it is not enabled.
  - Side note for our own code: this UE4SS build has
    `ExecuteInGameThreadAfterFrames`.
- Dragón: "ship it without logs nor spies nor anything that's development
  related — just the fixes and the new things you added, no test codes nor
  functions that didn't work". So, removed from `mod/` itself (source =
  shipped): the Profiler (Profiler.lua, main.lua wiring and every
  `Prof.start/stop`), HookConfig.lua and every `hooks_enabled` gate, and the
  [WON-OVER-SPY], [LEASH-SPY] and [PLAYER-SPY] blocks (plus
  `Personality.DescribeFight`/`fight_snapshot`, which only served them).
  profiletest.js was deleted with the Profiler. `tools/dev-instruments/` keeps
  HookConfig.lua (it was never committed); the rest is in git at `bd8e0ca`.
- `release/PalBonds-v1.1.4.zip` (12 files: LICENSE, README.txt, enabled.txt,
  9 scripts) plus both release trees are byte-identical to `mod/`, with
  DEBUG_LOGGING false everywhere and no dev instrument, checked by grep.
  Info.json is 1.1.4. The 1.1.3 zip was deleted, as with previous releases.
- README.txt: forgiveness is described; "a BONDED Pal that loses all its trust
  flees for good" (it used to say any Pal); the rule for hits below 50%; and
  the bug-report log path fixed to `Palworld/Pal/Binaries/Win64/palbonds-live.log`
  (it wrongly said "the mod's folder").
- The game's dev copy now holds the EXACT release scripts (logging off) for the
  smoke run.
- **Nexus: LIVE** (2026-09-18, 4:01PM page time): version 1.1.4, file
  "PalBonds V1.1.4", 271 KB. Dragón's own changelog is five one-liners.
- **Workshop: files prepared** in both copies: the upload folder
  (`steamapps/workshop/content/1623730/3797816321/`, 9 scripts, Info.json 1.1.4
  bumped in place with its BOM kept, `.workshop.json` untouched) and the game's
  NativeMods copy. Both are byte-identical to `release/workshop`, and Profiler.lua
  is gone from both. The local dev install was disabled for Dragón's Workshop
  smoke test and is **ENABLED again (2026-09-18, after the release)**: Dragón
  unticked the Workshop mods (no `ActiveModList`), and `dwmapi.dll` and
  `enabled.txt` are back. Development mode (Dragón, 2026-09-18): DEBUG_LOGGING is
  **true** in both `mod/` and the game copy, otherwise identical to 1.1.4. Set it
  back to false before the next release. Next work: the own-points rework.
- **Workshop pre-upload test: VALID, confirmed 2026-09-18.** Dragón enabled the
  Workshop mods and played; the pals stopped attacking at 20%. Afterwards:
  - Both copies were still byte-identical to 1.1.4, and Steam did NOT revert the
    upload folder to the published 1.1.3.
  - The game's NativeMods copy had a NEW timestamp (16:32, the moment he
    enabled the mods), while the upload folder kept mine (16:25). **So Palworld's
    mod manager re-copies from the Workshop content folder when mods are
    enabled.** Editing the upload folder is therefore enough to test before
    uploading. This refines the 2026-09-14 note that the copy is "written once
    and never re-synced": it isn't re-synced while the mods stay enabled, but
    enabling them copies it again.
  - The UE4SS.log proves the 1.1.4 code ran: 17 hooks, including the ESC-menu
    quit hooks that only exist in 1.1.4, and no errors.
- Still to do: the Workshop upload (Dragón, via the Mod Uploader), then GitHub, and fix the
  README.md known-issues entry. Also ask whether the Nexus/Workshop
  descriptions should mention forgiveness.
- **Next update's cleanup, not done now to keep the verified build unchanged:**
  old disabled mechanisms still sit in the code behind false flags. STILL
  PRESENT, verified 2026-09-23 in `Combat.lua`: `USE_OLD_MOVE_ORDER_NUDGE`,
  `USE_REPEATED_OTOMO_COMPOSITE`, `USE_ORBIT_WHEN_AT_GOAL`,
  `USE_MOVE_TO_ACTOR_FOLLOW`, `USE_NATIVE_LEASH_FOLLOW` -- all false. Audit and
  delete them.

**1.1.4 TEST RUN (2026-09-18, 15:10–15:25): PASSED.** Dragón: "everything
played nicely, game didn't crash either — pals actually forgive and can attack
back if hit again". Log:
- 7 Pals crossed 20% (Chikipi ×3, Samurai dog, FlowerDoll, two DreamDemons;
  rolled escape/normal/friendly/warlike_anyway/notinterested). 6 were released
  after about 3.1 s "NO LONGER angry"; the 7th was hit during its calm-down.
- **The "follows ITSELF" loose end is closed:** in the 20 s after release, no
  Pal ever targeted the player (`hateTarget=none` on every tick). Their actions
  went from finishing the pet/feed, to `BP_AIAction_FriendlyLookat_C` (the
  game's own "looks at you" idle), to `BP_AIAction_WildLife_C` (normal
  wandering). None was stuck in a follow action.
- 2 unbonded hits, both handled as specified: one after forgiveness (a Chikipi
  rolled Curious, reverted to 'friendly' = its original), and one during the
  calm-down (DreamDemon: "follow stopped: hit by the player during its
  calm-down", reverted to warlike_anyway with its own preset back). No
  betrayal, no errors, nothing FAILED.
- The quit hooks and world reset worked on two consecutive quits.
- Cheer: logged "call ok"; visual confirmation still pending.

**1.1.4 BUILD STATUS (2026-09-18):** the forgiveness rules below are
implemented in `mod/` and deployed to the game's dev copy for Dragón's test run.
All 17 harness suites pass; bosstest R1–R4, U1–U5 and G cover the rules, and
they fail against 1.1.3.
- Personality: `FRIENDLY_BRIEF_FOLLOW` and `legacy_friendly_reset` are GONE —
  the calm-down is the behaviour. `MaybeBecomeFriendlyByBar` saves
  `state.preForgive` (disposition, rolledTier, presetClassName) before
  `become_friendly_wild` overwrites rolledTier; `Personality.RevertForgiveness`
  restores the tag and writes back the rolled tier's donor preset (or the
  species preset for a Normal roll), re-sensing without a cancel. It consumes
  preForgive, and the `becameFriendlyByBar` latch is never cleared, which is
  what makes it one forgiveness per Pal.
- Trust: `on_unbonded_pal_hit_by_player` — reached from `OnFollowerDamaged` for
  a PLAYER hit on a Pal that is not following, or is in its calm-down. It ends
  the calm-down (clearing the `briefFollow` token first, so the release never
  writes Friendly), empties the bar, and calls RevertForgiveness. It has a 1 s
  dedupe, because both damage hooks report every hit.
- `Personality.WON_OVER_SPY` (ships false; TRUE in the game copy only) turns on
  the post-release watch without the rest of the diagnostics. Use it to see
  what a Pal does after the "follows ITSELF" release.
- The HookConfig BISECT/EMOTE_ONLY switches are removed. The hook GROUPS stay,
  all true.
- The cheer now goes through `ActionComponent:PlayAction` (logged "call ok"
  live). **Dragón still has to confirm his character visibly cheers.**

**Dragón's rulings, 2026-09-18 — BONDING AND BETRAYAL (read before touching either):**
- **"Bonding is a status that starts or should start at 50% friendship."**
  Nothing before 50% is a bond. Any comment or note saying "the bond starts at
  the first pet" is WRONG. Claude invented it from a misread report, and the
  pass-246/251 comments in Trust.lua say it; correct them when that code is
  next touched.
- His Gumoss report ("I could hit a partially-bonded Gumoss over and over with
  no penalty") meant **the Gumoss never attacked him back**. It did not mean it
  should have been punished.
- **Below 50%:** hitting a Pal is an ordinary fight. It defends itself from the
  player normally. No betrayal and no scarred status, because there is no bond
  yet.
- **What the code actually does (checked 2026-09-18):** `Trust.OnFollowerDamaged`
  exits unless `st.isFollowing`, so below 50% the penalty never ran. The rule is
  broken in exactly one place: **the 20% brief follow**, which sets
  `isFollowing`. A hit during the calm-down costs half the bar, which at 20–49%
  empties it, so it is full betrayal and the Pal is scarred. The companion
  preset also stops the Pal defending itself during those seconds.
- 1.1.4 = the crash fix plus the POLISHED 20% brief follow, shipped together.
  Wider self-defence reach is NOT in 1.1.4 (too many variables).
- The Mammorest falling through the floor is the base game (Pals align to the
  player's facing axis on uneven terrain). Not ours.
- The Proton reply goes out after 1.1.4 ships. No Steam-vs-Nexus recommendation:
  untested, and a second UE4SS install next to the first crashes the game.
- Dragón: **ask about doubts, don't advance on interpretations.**
- **The 20% calm-down, his full spec (2026-09-18):**
  1. A hit during the calm-down: the Pal reacts however its species normally
     would (some fight, some flee, e.g. Lifmunk). No forced "fight back".
  2. **A player hit below 50% drops the bar to 0.** Player hits only: Pal-vs-Pal
     damage never costs trust (his earlier ruling, quoted in Trust.lua). No
     betrayal and no scarred status, because there is no bond. Costs nothing
     measurable: the hit detection already runs for betrayal.
  3. The calm-down happens for EVERY Pal crossing 20%, not only hostile ones.
  4. After forgiving, the Pal acts completely normally, including getting angry
     again if hit or if a Pal of its species pulls it in. "We just need to
     trigger that brief forgiveness."
  5. It still defends its own kind. Don't interfere with an unbonded Pal beyond
     the forgiveness moment itself.
  6. **One forgiveness per Pal.** After that it is the player's carelessness —
     "we can't let them abuse the poor pals".
  7. When the bar drops to 0, the Pal goes back to its ORIGINAL rolled
     personality: tag AND AI preset (confirmed 2026-09-18). A Hostile Pal
     reads Hostile again, which he agrees is correct because it will attack.
  8. **Crossing 20% a second time does nothing at all:** no calm-down, no
     Friendly switch; it keeps its original personality. Bonding at 50% still
     works. His reason: "most pals will probably not survive too many hits from
     the player, so if we continue making them forgive or act differently, the
     pals will end up dying without having a chance to defend themselves with
     our meddling."

**Dragón's rulings, 2026-09-17 (start of the post-1.1.3 session):**
- **The world-change crash is BACK, reproducible, and now fixed in `mod/`
  (pass 328) — awaiting Dragón's live run.** Recipe he confirmed twice:
  interact with a wild Pal, have NOTHING following you, quit to the title,
  load a world -> `EXCEPTION_ACCESS_VIOLATION 0x338`. His 16:52-16:57 log has
  no `[WORLD-RESET]` line at all, which is the whole bug in one line.
  - **Cause:** the fast loop's world-change check sat BELOW
    `if next(BondingState) == nil then return end`, so with nothing bonded the
    loop returned before it ever looked at the player. No reset ran, PlayerRef
    kept the old world's character, and Indicator/Personality/Interaction had
    never been reset by anything. The 20% brief follow makes this easy to hit:
    it puts a Pal on the follower list and then takes it off, so a run ends
    with the tables empty and plenty still cached.
  - **Fix:** `world_change_watch()` above that early-out, timed off `os.clock`
    (1 s while a world is up, 2 s latched at the title, 0.2 s right after a
    quit is asked for) because the loop itself runs at 100 ms with a follower
    and 1000 ms idle — a pass count would have meant 10 s in exactly the idle
    state the crash happens in. It goes straight to `PlayerRef.Get()`: asking
    Combat's own `lastKnownPlayerActor:IsValid()` first reintroduced the 1.1.2
    bug inside the fix (caught by harness section D on its first run, not in
    game). A latch (`worldResetLatched`) makes the reset run exactly once per
    world change, and both older reset branches now share it instead of being
    gated on holding followers.
  - `Indicator.ResetForNewWorld`, `Personality.ResetForNewWorld` and
    `Interaction.ResetForNewWorld` are new and called from
    `Combat.ResetForNewWorld` (each in its own `safe_call`). Interaction
    deliberately keeps `cachedWorkerMenuParameter` (pass 285) and Personality
    keeps `presetCDOCache`.
  - **The game's own quit event, found in the object dump:**
    `WBP_MenuESC_C:ConfirmReturnTitle` and `:OnReturn2Title`, hooked with
    RegisterHook (retries 30 rounds, 2 s apart, like the nameplate hooks).
    They drop NOTHING — semantics unknown, and dropping state when a confirm
    box merely opens would break a bond the player then keeps. They call
    `Combat.ExpectWorldChange`, which tightens the watch to 0.2 s and puts
    `PlayerRef` into per-call engine liveness checks for 20 s
    (`PlayerRef.ExpectWorldChange`).
  - Hook count is now **17** (was 15); profiletest, harness3's README line and
    worldchangetest sections D/E cover all of this. The new checks fail on
    `release/PalBonds/Scripts` (1.1.3) as they should.
  - If this holds live, it ships as **1.1.4** with both feature switches off.
- **Second live run (17:45-17:46): STILL CRASHED, and the log settled the
  question the polling fix could not.** Everything new worked — the quit hooks
  installed (round 21), both fired at 17:46:48, the earlier world change at
  17:45:20 reset all six modules — and then the log simply ENDS at the confirm.
  **No further loop pass is ever serviced once a quit is confirmed**, so
  detecting the world change afterwards is impossible by construction. (Run 5's
  "LEASH-SPY stopped, then the crash" was the same signal, read as a symptom
  instead of a cause.)
  - **Second fix (same pass):** release everything INSIDE the hook.
    `Combat.OnQuitConfirmed` (wired to `ConfirmReturnTitle`) tells PlayerRef
    the world is closing and runs the full reset there and then, on the game
    thread, while the world is still alive. `OnReturn2Title` still only
    tightens the watch, so if it is the earlier of the two nothing is dropped
    at a prompt the player may cancel.
  - `PlayerRef.SetWorldClosing/IsWorldClosing/ProbeForNewPlayer`: while closing,
    `Get()` returns nil — which every caller already handles, since that is
    what the title screen looks like — so the nameplate hook, the personality
    resolver and the trust recorder cannot refill the tables in the moment
    between the confirm and the world actually dying.
    `Combat.IsShuttingDown()` now also returns true while closing, which is
    what Indicator's sweep and Trust's tick already consult.
  - How a closing world ends is decided by `ProbeForNewPlayer`: a player at a
    DIFFERENT address = the new world is up; the SAME player still there after
    `WORLD_CLOSING_CANCEL_SECONDS` (10 s) = the quit was cancelled, logged as
    `the quit was CANCELLED`, and the mod resumes in that world (bonds from
    before the prompt are gone — the deliberate trade).
  - Harness sections F and G cover the in-hook release and both endings.
- **Third live run (17:54-17:55): STILL CRASHED — and the log caught the mod IN
  THE ACT.** The release ran correctly at the confirm (1 bonding record, 8
  nameplate bars, 21 personality records dropped), and then one more line was
  written after it:
  `[PalBonds/Personality] unrecognized AIResponsePreset 'PalAIResponsePreset'`.
  That value is the engine's own base class name, which is what a read off a
  half-destroyed object returns — so a HOOK was still doing work during
  teardown, after the loop had stopped. Releasing what we hold was never going
  to be enough: the game keeps calling the functions we hooked while it tears
  the world down, and this UE4SS build cannot unregister a hook.
  - **Third fix (pass 329): the world-closing gate.** Every hook callback in
    Indicator, Personality, Trust and Interaction now starts with
    `if world_is_closing() then return end` (a local helper per file, one
    function call, no reflection). The mod goes deliberately blind from the
    confirm until the next world's character exists. The two ESC-menu quit
    hooks are NOT gated, for obvious reasons.
  - `PlayerRef.IsWorldClosing` gives up waiting after `CLOSING_MAX_SECONDS`
    (60 s) and logs `giving up waiting`: if Combat's watch ever stopped being
    serviced, a permanently closed gate would look exactly like "the mod
    stopped working", which is worse than one frame of crash risk.
  - Harness section H: the busiest hook (`PalHate:DamageEvent`) does nothing
    during teardown, and the gate opens again after the timeout.
- **Fourth live run (18:06-18:08): STILL CRASHED, and the log is SILENT from
  the confirm to the crash.** The gate holds — our Lua provably does nothing
  during teardown — so what remains that is ours is the mere EXISTENCE of the
  hooks. UE4SS's own log registers 23 hooks (10 of them script hooks inside UI
  blueprint classes that load on demand and are destroyed with the world) and
  prints `[FCallbackGarbageCollector] Freed invalid callbacks!` after a world
  change. **Stop theorising and bisect.**
  - `Scripts/HookConfig.lua` (pass 330): hook GROUPS, all shipping `true`
    (`nameplate`, `boss`, `radial`, `workermenu`, `quit`, `senses`,
    `itemslot`, `otomo`, `damage`). A group that is off never registers, which
    is the only way to remove a hook in this build. 17 hooks with all on, 14
    with nameplate+boss off.
  - **Run A (in progress):** PalBonds disabled (`enabled.txt.MODS-DISABLED`)
    with UE4SS still loaded and its own built-in mods (BPModLoaderMod,
    BPML_GenericFunctions, Keybinds) active. Same recipe. If that crashes, the
    crash is UE4SS's, not ours — and it would explain why three real fixes
    changed nothing. Never tested before: the earlier vanilla control had no
    UE4SS at all.
  - Then: groups off in halves (the five UI script-hook groups first), then
    narrow to the group.
- **THE CAUSE, CONFIRMED (pass 333): keybind callbacks do not run on the game
  thread.** Dragón's final control settled it: *pet only* = clean, *feed only*
  = clean, *Play (F8)* = crash. Pet and Feed arrive through `RegisterHook`,
  which fires inside the game's own call stack (game thread). F8 arrives
  through `RegisterKeyBind`, which UE4SS services on **its own thread** — and
  from there the mod was starting animations, allocating action objects and
  queueing montages straight into the engine. Nothing fails at the time; engine
  state is corrupted quietly and the next world load reads freed memory
  (0x338). Hence: four correct world-change fixes changing nothing, the two
  clean v1.1.1 runs being the pet-only and feed-only ones, and "an action that
  fails to play is safe" (a refused call touches nothing).
  - UE4SS's own maintainer says the same about their async entry points
    (narknon, issue #1345, quoted in docs/hook-points.md): use the
    in-game-thread helpers. The mod did that everywhere EXCEPT its keybinds.
  - **Fix:** `run_on_game_thread(fn)` in Interaction.lua — `ExecuteInGameThread`
    first, `ExecuteInGameThreadWithDelay(1, ...)` as a fallback, and a logged
    direct call only if neither exists. **All three keybinds** (F8 Play, F9
    tags, F10 passive gain) now hop before doing anything; F9 touches live
    widgets and F10 shows a toast, so both count as engine work.
  - Harness: every prelude's `ExecuteInGameThread` now runs its callback and
    counts it; shiptest asserts each keybind hops exactly once. Those checks
    fail on the old code.
  - **CONFIRMED LIVE, 2026-09-17 evening.** Dragón's verification run: bonding,
    pet, feed, play, capture, several world reloads — no crash. This is 1.1.4.
  - **Release checklist for the next session (nothing done yet):**
    1. `mod/` is the fix; `release/PalBonds/Scripts` and
       `release/workshop/PalBonds/Scripts` are still 1.1.3 — rebuild both.
    2. Logger `DEBUG_LOGGING = false` in the release copies (the dev copy in
       the game folder keeps it true).
    3. `HookConfig.lua` is NEW — it must be in the zip, the Workshop folder and
       both release trees, with every group `true` and `EMOTE_ONLY = false`.
    4. Both held-back switches stay false (`FRIENDLY_BRIEF_FOLLOW`,
       `SELF_DEFENCE_EXTENDED_REACH`).
    5. Info.json Version 1.1.4, new zip, README/known-issues entry, changelog
       (one line per change, no promises — see the memory on his public text),
       then Nexus, then Workshop, then GitHub.
    6. The old 1.1.3 "crash fixed" known-issue entry in README.md needs
       correcting: that fix was real but it was not this crash.
  - Dragón on the player impact: not worried, because Play is already
    described as experimental on both store pages — but he wants it fixed so it
    can be used safely.
- **CORRECTION (pass 332, same evening): the `{}`-struct conclusion below was
  WRONG, and the log said so.** With every field of FActionDynamicParameter
  spelled out, UE4SS refused the call — `[push_classproperty] Error` — so the
  cheer never played. That run was clean for the same reason every clean run
  was clean: **no action was ever started.** Do not re-adopt the struct theory
  without a log line showing the emote actually playing.
  - Re-routing the cheer through `UPalActionComponent::PlayAction(pawn, cls)`
    (no struct at all) works — `[EMOTE] ... call ok` — and still crashes. That
    route is kept anyway: it is simpler, local, and has no parameter block.
  - **What IS established, from nine bisect runs:** reads, aiming and target
    resolution are safe; an action that PLAYS (on the player or on a Pal)
    poisons the next world load; an action that FAILS to play does not.
  - **The one hypothesis that fits everything, including the v1.1.1 runs:** the
    poison is an action **this mod starts directly**. Dragón's two clean 1.1.1
    runs were *pet only* and *feed only* — and the radial Pet/Feed path plays
    NOTHING itself (`grant_wild_interaction` is bookkeeping only; the GAME
    starts its own action there). Every crashing run today used F8 Play, which
    is where the mod's own `PlayActionByType` calls live.
  - **The mod's direct action plays, the complete list:** `do_play`'s
    `PlayActionByType(pal, PalRandomRest=77)` and its `Happy` follow-up
    (Interaction.lua ~765 and ~851), the player cheer (~1700), and Capture's
    join celebration `PlayActionByType(pal, 38)` (Capture.lua ~649).
  - **Next control (cheapest decisive run):** full mod, **no F8 at all** —
    radial Pet and Feed only — then quit and load. Clean = the rule holds, and
    the fix direction is to route Play through the game's own action start (the
    same substitution trick Pet already uses) instead of calling PlayActionByType.
  - **Player-facing consequence if it holds:** shipped 1.1.3 can crash for
    anyone who uses Play (F8) and then loads another world without restarting.
    Pet/Feed-only players are unaffected. Worth saying plainly in the 1.1.4
    notes once proven.
- **The (WRONG) conclusion of pass 331, kept for the record:** `{}` passed as a STRUCT.
  `play_player_emote` called
  `pc:ActionComponent_PlayAction_ToServer_ForPlayer(pawn, {}, cls, 0)` —
  copied verbatim from the Kick Keybind reference mod. That second argument is
  **`FActionDynamicParameter`, 0x100 bytes**: an actor pointer, a `TArray` of
  actors, an `FTransform`, two `FGuid`s and an `FPalNetArchive`. An empty Lua
  table leaves that memory as it was; the game copies the block into the action
  it creates and frees parts of it later. Nothing fails when the emote plays or
  when the world closes — it fails when the NEXT world loads into that memory.
  Hence four correct fixes to the quit path changing nothing.
  - **Dragón's bisect, one run each** (his own controls did the most work):
    UE4SS alone = clean; UI hooks off = crash; ALL hooks off = crash; no F8 =
    clean; F8 with no Pal nearby = clean; brief follow off = crash; trust grant
    off = crash; Pal animation only = crash; **player emote only, no Pal at
    all = crash**; same emote with every field spelled out = **CLEAN**
    (several loads, F8 spammed).
  - **Fix:** fill every field of the block, unconditionally. The switch used to
    prove it is gone. `Interaction.PlayPlayerEmote` is exported so the harness
    can fire the call directly; playstoptest asserts every field, and those
    checks fail on the old one-liner.
  - **Rule for this project from now on: an empty table is not an empty
    struct.** Any UFunction argument that is a struct gets every field spelled
    out. A grep found no other `{}` argument in the mod.
  - `Scripts/HookConfig.lua` stays (all groups true) — it turned a blind hunt
    into nine decisive runs, and it is the tool to reach for the next time
    something crashes only in game.
  - **Still to verify:** the full mod with the fix (the Pal-animation bisect run
    crashed too, and that call passes no struct — so either it shares the same
    poisoned memory or there is a second, smaller cause). If the full mod is
    clean, this ships as **1.1.4**.
  - **Answers for Dragón's questions, for the record:** the crash is inside
    the game's code but reached THROUGH our hooks (UE4SS frames sit mid-stack);
    and a "clean up on mod load" cannot help, because the mod loads once per
    game launch, nothing is persisted to disk, and the damage is done while the
    old world dies.
    **Watch for in the next log:** whether a CANCELLED line ever appears when
    Dragón confirms (it must not), and whether `ConfirmReturnTitle` fires on a
    cancelled prompt.
- **Bonded-Pal despawn:** stays a known issue.
- **Three-boss layout:** Dragón will test it himself with a spawn/cheat mod.
- **Own trust points (Dragón's idea, under discussion):** stop driving the bar
  from the game's `FriendshipPoint` and keep PalBonds' own points instead,
  granting the real trust only as the end-of-bond bonus. This would remove the
  game's own +10 after a pet from the bar, and would make per-interaction
  values fully ours to configure.
- **Settings screen wishlist (Dragón):**
  - language for toasts and tags (EN, ES, BR, JA, ...);
  - end-of-bond trust bonus, 0 to 200000 (max trust rank);
  - personality spawn weights (`PERSONALITY_TIERS`);
  - value per interaction;
  - rebindable Play / tags / passive-gain keys.
  - **Dragón's call:** the goal is an in-game menu, starting with a settings
    file first. Still open: where a user config survives Workshop updates.
    - **Candidate answer (from Random Sized Pals, 2026-09-18):** do NOT ship
      the config file. The mod writes a default `config.lua` beside `main.lua`
      on first run (write to `.tmp`, then rename) and `dofile`s it after that. A
      Workshop update replaces only shipped files, so an unshipped config
      survives. That is their claim and it is unverified here. Test it against
      the Workshop re-copy behaviour we found for 1.1.4 (the game re-copies the
      content folder when mods are enabled) before relying on it.
  - Own points: Dragón is interested; details later.
  - **DarnMenu 1.8.11 studied (2026-09-18).** Dragón put a copy in
    `32-PalBonds/DarnMenu 1.8.11 .../` to learn from, not as a dependency.
    Its licence: "free to use and modify".
    - **An in-game settings screen IS possible from pure Lua, with no pak and
      no Unreal editor.** This corrects what I said earlier. It uses
      `NotifyOnNewObject` on `WBP_MenuESC_C`, then after 50 ms (never inside
      the construction callback: AV writing 0x80) it constructs the game's own
      `WBP_MenuESC_Button_S_C` with `StaticConstructObject` under "Link
      Discord". Clicks come through a `RegisterHook` on that button class. The
      page is built from UMG CanvasPanel/ScrollBox/SizeBox.
    - Cost: ui.lua is 200 KB plus main.lua 176 KB, and full of crash lessons.
      Widget churn inside an open menu is their crash family, and a pre-build
      of about 100 widgets per ESC open caused 7 incidents before it was
      switched off.
    - **Config location: `Mods/shared/<name>_user.lua`, outside the mod
      folder,** because mod updates replace the folder. `Mods/shared` already
      exists in the Workshop UE4SS install (it is UE4SS's own library folder,
      with UEHelpers). Unverified: whether it survives a Workshop UE4SS
      update/re-copy. Test with a marker file in both `shared/` and our mod
      folder, across a Workshop enable.
    - Optional integration route: a mod writes
      `shared/DarnMenu_schema_<Name>.lua` and adds itself to
      `shared/DarnMenu_schema_index.lua`. With DarnMenu installed a page appears
      under ESC → Mod Options; without it nothing happens. Values apply at the
      next launch, or live via file polling.
    - Lessons that match ours: RegisterKeyBind runs off the game thread, so hop
      before touching UObjects (they crashed on it too; our 1.1.4 fix); gate
      work during map loads; write atomically (tmp → .bak → rename); "don't take
      the player's keys". `ExecuteWithDelay` (async) leaks a registry slot per
      fire, according to their reading of the UE4SS source. PalBonds uses only
      the game-thread `ExecuteInGameThreadWithDelay` plus the dead `LoopAsync`
      fallbacks.
  - **Creative Menu 1.2.4 studied (2026-09-23, Dragón asked whether we could
    make our menu like its F1 screen).** It is NOT a Lua mod and there is no
    technique to copy: its UI ships as cooked Blueprint/UMG assets in
    `Paks/CreativeMenu_P.pak` (~570 KB, widgets under
    `/Game/Pal/Mods/CreativeMenu/BP/UI/...`), loaded through the game's own
    PalModLoader (`/Game/Pal/PalModLoader/BP_Base`, `WBP_UI`). Its leftover
    LogicMods pak says the LogicMod version is retired and UE4SS is no longer
    needed for it. Reproducing that route needs the Unreal editor plus
    Palworld's asset set and a cooked pak -- a different toolchain from ours.
    The DarnMenu finding above stands as our route: a settings screen in pure
    Lua, attached to the ESC menu rather than a key of its own.
- **1.1.5 CONTENT COMPLETE AND LIVE-TESTED (2026-09-18, end of day).**
  Dragón: "we will consider this the new most recent stable version". Pushed
  to GitHub. Tomorrow (09-19) is release packaging only, the usual steps:
  DEBUG_LOGGING back to false; README.txt, README.md and store text (the
  settings section drafted 2026-09-18 in chat: where the file is, how to edit
  it, "an in-game settings screen is planned for a future update"; the
  languages line; keys changeable); changelog; Info.json 1.1.5; zip; Nexus;
  Workshop pre-upload test, which also checks that PalBonds_settings.lua lands
  in and survives `Mods/NativeMods/UE4SS/Mods/shared/`; GitHub release notes.
  Dragón re-edits his 16 Workshop descriptions with the translated tag names
  (from docs/translations-review.md) and fixes "Tímid".
- **1.1.5 PACKAGED (2026-09-19, morning).** DEBUG_LOGGING false in `mod/`;
  all 21 suites pass, 17 hooks. `release/PalBonds-v1.1.5.zip` (14 files:
  LICENSE from the repo root, README.txt, enabled.txt, 11 scripts incl.
  Locale.lua and Settings.lua) verified byte-identical to `mod/`; the 1.1.4 zip
  deleted as usual. Both release trees and the game's manual-install copy are
  identical to `mod/`. `release/workshop/PalBonds/Info.json` is 1.1.5 (that copy
  has no BOM; the upload folder's does, so bump that one in place).
  README.txt: SETTINGS section, languages and settings bullets, keys
  changeable, the half-bar bonded hit, despawn message. README.md: the same
  plus a Settings section and a note on the despawn known issue.
  `nexus-description.txt`: Settings and Your language sections.
  The Workshop UE4SS has `Mods/NativeMods/UE4SS/Mods/shared/` (UEHelpers in
  it), so the settings path holds there; the Workshop test confirms it live.
  Order today: Nexus first, then the Workshop.
  - **Nexus: LIVE** (checked 2026-09-19): version 1.1.5, main file "PalBonds
    V1.1.5", 288 KB (= our zip), Dragón's changelog (8 one-liners) and short
    description. `release/nexus-description.txt` synced to the live page.
    Terminology in player text (Dragón): the game's UI calls its value
    "Trust", so where both appear (changelog) our bar is the "friendship bar";
    other texts keep "trust bar" as they are.
  - **Dev install DISABLED** for the Workshop test (`dwmapi.dll` and
    `ue4ss/Mods/PalBonds/enabled.txt` → `*.MODS-DISABLED`).
  - **Workshop upload folder prepared:** 11 scripts identical to
    `release/workshop`, Info.json 1.1.5 with its BOM kept, `.workshop.json`
    untouched. Next: Dragón ticks the Workshop mods and tests, then uploads.
  - **Workshop pre-upload test PASSED (2026-09-19, 12:26-12:30).** The
    NativeMods copy (re-copied 12:26) is identical to the release, 11 scripts.
    The settings file was CREATED in `Mods/NativeMods/UE4SS/Mods/shared/` on
    the first launch (12:26) and LOADED on the next one (UE4SS.log 12:29:
    "[SETTINGS] loaded .../NativeMods/UE4SS/Mods/shared/PalBonds_settings.lua"),
    17 hooks, no Lua errors. So the Workshop settings path is confirmed.
    Still unobserved: the file surviving a real Steam update of the item
    (it lives outside the PalBonds folder the update replaces).
  - **Workshop: LIVE** (checked 2026-09-19): updated 19 Sep @ 12:40pm, change
    note "Version 1.1.5" with the same 8 lines as Nexus, `.workshop.json`
    `last_published_version` 1.1.5, upload folder still identical to the
    release. English description has the Settings section (Steam route +
    `Mods/NativeMods/UE4SS/Mods/shared/`), the keys line, the language bullet
    and Known Issues; `release/workshop-description.txt` synced. Dragón still has
    to update the 16 translated descriptions. Dev install still DISABLED.
    Left: GitHub commit + release notes (ask first).
- **1.1.6 PACKAGED (2026-09-20, morning) — NOT yet uploaded.** Dragón's call
  that morning: Esaeon never answered, so 1.1.6 ships without any claim about
  the Proton crash, and niconoko's request goes in because it is small.
  - **New setting `ShowPersonalityTags`** (DISPLAY section, 1/0, default 1):
    where the tags START; the Tags key still toggles them from there.
    `Indicator.lua` reads it at load. niconoko (Nexus, 19 Sep): they did not
    want to press the key every session.
  - **Settings added by a later version are now appended to the player's own
    file** (`Settings.TextWithMissingKeys` + `Settings.AppendedTextIsGood`).
    It is an INSERTION before the file's last `}`, never a rewrite, and the
    result is parsed back in an empty environment and checked (every player
    value survived, every new key at its default) before anything is written;
    if the check fails the file is left alone and the console says so. This was
    the scaling problem with the old "never rewrite" rule: every future setting
    would have asked every existing player to delete their file.
  - **Dev instrumentation removed:** `DevWatch.lua` deleted with its four call
    sites (`Interaction.lua` x3, `main.lua`), `Logger.DebugEnabled` deleted
    (only DevWatch used it), `DEBUG_LOGGING = false`, `TRACE_PHASES = false`.
    `Logger.trace` and its call sites STAY, inert: a future test build is one
    flag away. Hooks back to 17 (the two `[BOSS-REWARD]` ones were DevWatch's).
  - **Tests:** settingstest.js sections H (append: added once, own values and
    own text kept, idempotent on the next launch, no-comma and empty files,
    every refusal case of the safety check) and I (the tags start from the
    file). All 22 suites pass against `mod/` AND against
    `release/PalBonds/Scripts`; undefcheck 4 / hoistcheck 2 known false
    positives.
  - **Packaged:** `release/PalBonds-v1.1.6.zip` (14 files, 298 KB), both
    release trees re-synced, `release/workshop/PalBonds/Info.json` → 1.1.6,
    README.txt (x2), README.md and both store descriptions updated (the new
    setting, the append behaviour, and bosses counting as defeated). The 1.1.5
    zip is still there; delete it once 1.1.6 is live.
  - **Deployed to both live installs** (manual `ue4ss/Mods/PalBonds/Scripts`
    and `Mods/NativeMods/UE4SS/Mods/PalBonds/Scripts`), md5-verified, DevWatch
    deleted from the manual copy. The manual loader (`dwmapi.dll`) is enabled.
    Dragón's live settings file is a 1.1.5-era one with no
    `ShowPersonalityTags`, so his next launch is a real test of the append.
  - **FOUND LIVE, run 1 (2026-09-20 14:33): `os.rename` cannot overwrite on
    Windows.** The append built the right text and passed its own safety check,
    then `[SETTINGS] could not write ... — ShowPersonalityTags use their
    defaults`. `write_text_file` wrote `<file>.tmp` and renamed it over the
    target, which works only when the target does not exist — i.e. only when
    CREATING the file, never when replacing one. Every existing player would
    have seen exactly this. Fixed with the move-aside dance DarnMenu also uses:
    tmp → move the current file to `.bak` → rename tmp into place → delete the
    `.bak`, and on any failure the `.bak` goes straight back. **The harness's
    fake `os.rename` now fails when the destination exists, like Windows** —
    it happily overwrote before, which is why 22 green suites still shipped a
    file the game could not write. Tests added for the failed-write path (the
    player's file untouched, no `.tmp`/`.bak` left, console message).
  - **Nexus: LIVE** (checked 2026-09-20): version 1.1.6, "PalBonds V1.1.6",
    297 KB, uploaded 3:01PM, Dragón's six-line changelog and his short
    description. The page description was NOT touched and must not be.
  - **STORE DESCRIPTIONS ARE NOT PART OF A RELEASE (Dragón, 2026-09-20).** I had
    edited both description files for 1.1.6; he told me to revert them: "we are
    not changing the descriptions until i deem it necesary, not for every small
    change we add." The description is already long enough that players skip it
    — his proof is the Steam commenter who asked about multiplayer when the
    description says it is singleplayer-tested only. Both `.txt` files were
    reverted to the live 1.1.5 text. **Planned instead: trim the descriptions
    around 1.2.0**, once several things have settled — the next description work
    is a cut, not an addition.
  - **Workshop staged and live-tested (2026-09-20).** Dev install disabled
    (`dwmapi.dll` and `ue4ss/Mods/PalBonds/enabled.txt` → `*.MODS-DISABLED`).
    Upload folder: 11 scripts md5-identical to `release/workshop`, Info.json
    1.1.6 with its BOM, `.workshop.json` untouched (still 1.1.5 until the
    uploader rewrites it). Dragón's Workshop run was clean, and the append ran
    a second time on the Workshop path: `Mods/NativeMods/UE4SS/Mods/shared/`
    took `ShowPersonalityTags` at 15:09 with no `.tmp`/`.bak` left behind.
  - **Workshop: LIVE** (checked 2026-09-20): change note "Version 1.1.6" with
    the six lines, dated 20 SEP 11:17 Steam time. **`.workshop.json` was
    touched at publish time but still reads `last_published_version` 1.1.5** —
    the same inconsistency seen at 1.1.3 (it kept 1.1.1) while 1.1.5 did write
    back. So that field is NOT a reliable publish check; read the item's
    change-note page instead. Descriptions untouched on both stores.
  - **Left:** GitHub (commit, release notes) and the merge of
    `test/join-cleanup` into `master`.
- **ESAEON'S CRASH: SOLVED, AND IT WAS NOT OURS (2026-09-20).** Their own
  investigation on GitHub #1: every crash in the thread — the preset builder,
  the pet check, the nameplate sweep — had the identical native stack, all
  frames inside UE4SS, none in the game. All of them ran on **UE4SS v3.0.1
  Beta Git SHA `c838a8ac` (15 July 2026)**, a build that appears in UE4SS-RE's
  own tracker for a separate native crash (UE4SS-RE/RE-UE4SS#1351). Updating
  to **Okaetsu's `2281fa31` (3 Sept 2026)** fixed every one of them with **no
  PalBonds change**, verified with the four-run protocol from
  `docs/crash-testing-guide.md`: runs A–D clean, 426 nameplate scans all
  paired, the session ending on a normal tick instead of a cutoff.
  - **Verified here:** the Workshop UE4SS on Dragón's machine IS `2281fa31`,
    so Workshop players get the good build with the dependency. The manual dev
    install is `ba2efd55`, a different build again — worth remembering that we
    develop on a build no player necessarily runs.
  - **What this means for the mod:** three of our defensive fixes (join
    cleanup, sensor checks, the pose release) were built while chasing this and
    are good in their own right, but none of them was the cause. The remaining
    crash report to watch is Toxik's, on Windows with ~40 mods, which is NOT
    assumed to be the same thing (Dragón's ruling).
  - **Open question for Dragón:** whether the mod page should carry a line
    telling manual-install players to update UE4SS if theirs predates
    September 2026. That is a requirement fact, not a feature blurb, so it is
    worth asking even under the "descriptions are not part of a release" rule.
  - Left: reply on Nexus (drafted), then a comment on GitHub #1 and closing
    it — his call, and nothing posted without it.
- **MULTIPLAYER, STEP 1 — WHICH PLAYER IS OURS (2026-09-20, built, tests pass,
  deployed, NOT yet seen in game).** Dragón chose multiplayer as the next work
  and agreed with starting here: "first check which player is doing the things
  so cross player's captures or join dont get mess up". Releasing Pals back to
  the wild stays AFTER multiplayer and the settings screen — "its an extra out
  of scope from this project".
  - **The bug:** every player lookup took the FIRST valid `PalPlayerCharacter`
    in the object list. One player in singleplayer, so always right; in co-op
    every player's character is loaded on every machine, which is how
    LuWicki97 (Workshop, 2026-09-15) watched the Digtoise HE befriended join
    his friend's party.
  - **The fix:** `PlayerRef.pick_local` prefers the character this machine
    controls (`APawn::IsLocallyControlled`, Engine.hpp 8884; the controller
    twin `IsLocalPlayerController` is 8289). `search()` and
    `ProbeForNewPlayer` both use it, so another player's character can no
    longer be mistaken for "a new world loaded" either.
    `Interaction.find_player_controller`'s fallback list prefers the local
    controller the same way (UEHelpers' own GetPlayerController is NOT
    co-op-safe: it accepts any `IsPlayerController()`).
  - **What happens when the question is not answered** (the part that matters):
    somebody says true → that one, wherever it sits; nobody says true, exactly
    one character, and nothing has ever answered true this session → that one,
    so a build that cannot answer keeps singleplayer working exactly as before;
    nobody says true with several characters and the call never worked → the
    first one plus one log line, rather than going blind; otherwise → nil, and
    the caller retries (it never latches). Once anything HAS answered true the
    answer is believed, so a lone character that says "not yours" is not
    adopted.
  - **One `[PLAYER-LIFE]` line per session says HOW our character was
    recognised** — that is the only way to learn from a player's log whether
    this build answers the question at all, which decides whether co-op can
    work.
  - **Tests:** `tools/harness/multiplayertest.js` (A–E, 30 checks). Verified
    against the shipped 1.1.6 code: the four behavioural checks fail there
    (Get picks the wrong player, a foreign character reads as a new world, the
    emote plays on the wrong pawn) while the no-regression check still passes.
    23 suites pass on `mod/`.
  - **Deployed to the manual install only**, with `DEBUG_LOGGING = true` in the
    game copy's Logger.lua (mod/ stays false). The NativeMods copy is left at
    the released 1.1.6.
  - **RUN 1 (2026-09-20, 16:19-16:26): the engine ANSWERS.** `[PLAYER-LIFE] our
    player character is the one this machine controls (IsLocallyControlled),
    out of 1 in this world`. Singleplayer played normally, no Lua errors, and
    the second line of the run is a bonus: at the world change the remaining
    character stopped being locally controlled, which is now another way the
    mod notices the world going away (the reset fired in the same second).
    So co-op can be built on this call.
  - **Next:** a co-op reconnaissance session with a friend, both with the mod,
    to see what already works before any further co-op code.
- **DUPLICATE "starts following you" MESSAGE — FOUND AND FIXED (2026-09-20).**
  Dragón, on his second Petallia: "i think i saw the follow toast twice". The
  log proves it: interaction #2 crossed 50% (told), the passive tick then hit
  the capture threshold — and `maybe_trigger_capture` clears `isFollowing` so
  the follower tick lets go — and interaction #3, landing inside the 5 s wait
  before the join, looked like a fresh 50% crossing. `OnInteractionSucceeded`
  now also requires `not st.captureTriggered` before starting a follow. Test
  `pointstest.js` P13 replays that exact sequence and fails on the shipped
  1.1.6 code (two toasts, "bonding bar crossed" twice).
- **MISSING TRUST BAR — ROOT CAUSE FOUND AND FIXED (2026-09-20, second
  occurrence: Lullu / `BP_LeafPrincess_C`).** Dragón reproduced it in a
  singleplayer run with full diagnostics on. Lullu was fed 13 s after a world
  reload, bonded, followed him, sat on screen for 17 s (AIM-FREEZE lines) — and
  Indicator never once created widgets for her gauge; only 3 gauges were ever
  built in that world.
  - **Mechanism, certain from the code:** a nameplate can find its Pal ONLY
    through the handle the `BindFromHandle` hook hands us (`gaugeHandleByKey`);
    the widget's own `bindedHandle` field is unreadable in this UE4SS build
    (fifty-ninth pass). So a nameplate whose bind we lost can never show a tag
    or bar, and no sweep can recover it, until the game rebinds that widget.
  - **Where the binds were lost:** `Indicator.ResetForNewWorld` wiped
    `gaugeHandleByKey`. The reload is noticed by polling a moment AFTER the new
    world starts loading — both logs show the new world's Pals being rolled a
    second before the reset line — so the new world's nameplates were already
    bound and the reset threw those binds away with the old world's.
  - Both cases (Petallia 16:25, Lullu 20:46) were bonded within ~20 s of a
    reload; the run that did not reproduce it waited longer. NOT caused by the
    guest gate: the Petallia case predates `Session.lua`.
  - **Fix:** the bind hook records when each nameplate was bound
    (`gaugeBoundAt`); the reset keeps binds from the last 20 s
    (`NEW_WORLD_BIND_GRACE_SECONDS`) and re-queues them, and drops older ones as
    before. A kept handle that proves to be the old world's simply fails to
    resolve. `worldchangetest.js` section I.
- **(superseded) MISSING TRUST BAR ON THAT SAME PETALLIA — open, needs one run.** He saw no
  friendship bar on her at all, having started with a Play interaction. The
  log cannot answer it: every Indicator install/scan line is diagnostic-tagged
  and was filtered out of that run. Two candidates, and they are distinguished
  by whether a world reload happened first:
    a) something about installing NEW nameplate bars breaks after a world
       reload (that world was the reloaded one, and only 2 nameplate bars were
       ever tracked in it, against 35 in the first);
    b) nothing is broken: he played her from 804 units (the Play limit is 900),
       where the game shows no nameplate at all, and once he got close she was
       ~5 s from joining.
  **Set up for it (2026-09-20):** the game copy now has `DEBUG_LOGGING = true`
  AND `SHOW_DIAGNOSTICS = true` (mod/ stays false on both). Protocol given to
  Dragón: fresh launch, walk CLOSE to a wild Pal so its nameplate is on
  screen, pet once, look for the bar; then quit to title, load again, and do
  exactly the same with another Pal. Report which of the two showed a bar.
- **1.1.5 PLAN (Dragón, 2026-09-18): ship TOMORROW (09-19), not today, with the
  own-points rework plus the settings file ("either if we finish the settings
  file or not"). Two uploads a few hours apart made no sense, and the 1.1.4
  bugs it fixes are mild.**
- **SETTINGS FILE v1 — IMPLEMENTED 2026-09-18, awaiting a live run.**
  Dragón's scope: everything on the wishlist except language, as plain numbers
  ("percentages would destroy the purpose to have multipliers per level").
  - `Scripts/Settings.lua`, required first by Interaction, Trust, Capture,
    Personality and Indicator. It writes `PalBonds_settings.lua` on first
    launch into UE4SS's `Mods/shared/` (falling back to our mod folder if
    that isn't writable) via tmp + rename, and reads it once at launch.
    Changes apply on the next launch.
  - Keys: Pet, Play, FeedBase, FeedBonusCommon..Legendary, KinshipPeachLesser,
    KinshipPeach, PassivePerTick, JoinBonus (0–200000), ChanceNormal..Feral
    (weights 0–1000; if all are 0 the defaults apply), KeyPlay/KeyTags/
    KeyPassiveGain (validated against UE4SS's `Key` table, case-insensitive).
  - Rules: the file is loaded with an EMPTY environment (it can only return
    values). A bad value uses its default and is reported on the UE4SS
    console (`[PalBonds] [SETTINGS]`, via print, so it shows in a release
    build). An unparseable file is left untouched and all defaults apply.
    An existing file is NEVER rewritten; settings added later use their
    defaults. Unknown names are reported as typos.
  - Tests: `tools/harness/settingstest.js` (in-memory file system; A–G).
    pointstest's join check now reads the setting. `undefcheck.py` knows
    `loadfile`. 20 suites pass, 17 hooks.
  - Still to verify: that the file survives a Workshop update / re-copy in
    `shared/`. Plan: tomorrow's Workshop pre-upload test doubles as that check.
    README.txt/README.md/store text need a settings section at release.
  - **Language (asked 2026-09-18):** about 22 short strings (7 toasts, 4
    toggle toasts, 11 tags/labels). The code is small; the open parts are
    writing and checking the translations (Dragón has Steam description
    translations in ~10 languages to align terms with), whether non-English
    characters survive UE4SS's Lua-to-game text conversion (needs one live
    toast test), whether longer words fit the tag under the health bar, and
    whether to follow the game's language automatically.
    - **Dragón's Workshop description exists in 16 languages besides
      English** (2026-09-16/17): Simplified and Traditional Chinese, Japanese,
      Korean, Thai, Indonesian, German, Spanish (Spain), Spanish (Latin
      America), French, Italian, Polish, Portuguese (Brazil), Russian,
      Turkish, Vietnamese. To read one, add Steam's language parameter to the
      Workshop URL (`...?id=3797816321&l=spanish`; others: schinese,
      tchinese, japanese, koreana, thai, indonesian, german, latam, french,
      italian, polish, brazilian, russian, turkish, vietnamese) and read
      `.workshopItemDescription` in the browser. Verified with `spanish` on
      2026-09-18. Use these to keep the mod's terms matching the description.
    - Language work is AFTER 1.1.5.
  - Committed + pushed 2026-09-18 (`0a13eb9`, Dragón's go-ahead): the points
    rework, despawn changes and settings, with DEBUG_LOGGING still on in
    `mod/`. The DarnMenu reference folder is git-ignored (not ours to
    redistribute).
  - Settings live run 1: the file was created in `ue4ss/Mods/shared/` on
    first launch (console line OK). Fixed afterwards: the line printed twice
    in dev mode (Logger also prints) and showed `Scripts/../../shared`;
    `tidy_path` now cleans it. For run 2 the game's file has test values:
    Pet = 200, KeyPlay = "F7", and a deliberate typo `Petting = 5`. Delete
    the file after the run to restore the defaults.
  - **Settings live run 2: PASSED (2026-09-18).** UE4SS.log showed a clean
    "loaded .../ue4ss/Mods/shared/PalBonds_settings.lua" line and `"Petting" is
    not a PalBonds setting (typo?) — ignored`, each once. The first pet gave
    trust 200; F7 played and F8 did nothing (Dragón confirmed in game; the log
    shows "F7 pressed — starting Play"). The test file was deleted afterwards,
    so the next launch recreates the defaults.
  - **Language, Dragón's call (2026-09-18):** follow the game's language
    automatically IF WE CAN, otherwise default to English. Lead:
    `UKismetInternationalizationLibrary::GetCurrentLanguage()` /
    `GetCurrentCulture()` (Engine.hpp 13925, no parameters, returns an
    FString). Unknown: whether Palworld's in-game language option (it has its
    own `EPalLanguageType`, and its text lives in per-language DataTables
    rather than .locres) changes the engine culture, or whether that reports
    the Steam/OS language. Needs one read-only probe run: log both, then
    switch the in-game language and relaunch. After 1.1.5.
  - **LANG PROBE ARMED in the GAME COPY ONLY (2026-09-18, Dragón asked for the
    test now):** `Scripts/LangProbe.lua`, plus a `pcall(require, "LangProbe")`
    line at the end of the game copy's main.lua. F6 logs `[LANG-PROBE] engine
    language = ... | engine culture = ...` and shows 3 toasts in Latin with
    accents, Cyrillic, Vietnamese, Thai, Chinese, Japanese and Korean. `mod/`
    and git are untouched. **DELETE both after the run**; the game copy must
    match `mod/` again before the 1.1.5 Workshop test.
    - **Probe run 1 (2026-09-18): every script renders correctly in the
      game's toast**, in English and in Spanish: accented Latin, Polish,
      Turkish, Cyrillic, Vietnamese, Thai (including combining marks),
      Chinese (simplified and traditional), Japanese and Korean. So UE4SS's
      Lua → FText conversion is UTF-8-safe. One quirk: `|` displays as a
      quote-like mark, so avoid it in player text.
    - **Engine reading FOLLOWS the in-game language: auto-detection is
      possible.** English session: `language = en | culture = en` (Dragón
      confirmed the pasted console was from the English launch). Spanish
      session (probe run 2, 20:51): `language = es-MX | culture = es-MX`. Read
      with `StaticFindObject("/Script/Engine.Default__KismetInternationalizationLibrary")
      :GetCurrentLanguage()`, returning an FString (`:ToString()`), called on
      the game thread without trouble. Map culture to translation: exact code
      first (es-MX = Latin America, pt-BR, zh-Hans/zh-Hant), then the part
      before "-", else English (Dragón's fallback). Still to confirm: what
      code the Spain-Spanish and Chinese options report.
    - The probe was REMOVED from the game copy after run 2; the game copy
      matches `mod/` again.
  - **TRANSLATIONS — IMPLEMENTED 2026-09-18 for 1.1.5 (Dragón: "why not do
    the translations now so we can ship them tomorrow too"), awaiting a live
    run.**
    - Dragón's rulings: translate the TAGS too. He will re-edit his 16
      Workshop descriptions once 1.1.5 is uploaded; they currently name the
      tags in English on purpose, and "Tímid" is his typo to fix then. Use
      ONE neutral Spanish set for Spain and Latin America, like his
      descriptions.
    - `Scripts/Locale.lua`: 23 strings (12 tags, 6 messages, "A Pal", 4
      F9/F10 toasts) × 16 sets (en, es, fr, de, it, pl, pt, ru, tr, vi, th,
      id, ja, ko, zh-hans, zh-hant). Wording follows his Workshop
      translations where they already name things (tags = "etiquetas de
      personalidad"/"性格タグ"/…, passive friendship gain, trust, giving up
      on you). Feral avoids each language's word for "wild" (Feroz, Rasend,
      Szalony, Azgın…), since every tagged Pal is wild. Scarred is an
      emotional word (Resentido, Verbittert, Kırgın, 心寒…).
    - `Locale.T(key, {name=})` and `Locale.FromCulture(code)`. "auto" reads
      the engine's GetCurrentLanguage at most every 10 s (only from game-thread
      callers: tag refresh and toasts); an unknown code or a failed call
      means English. Settings got `Language` ("auto" or a listed code, in its
      own LANGUAGE section; existing files default to auto).
    - Wired: Indicator's tag maps now hold keys, Capture's
      joined/betrayed/fell/abandoned/shaken toasts, and Interaction's F9/F10
      toasts. Tags refresh on their own, so a language change shows up
      mid-game.
    - Tests: `tools/harness/localetest.js` (A–E); settingstest gained
      Language checks. 22 suites pass, 17 hooks.
    - To verify live: the wording reads naturally (Dragón can judge
      Spanish), and long tags fit under the health bar (German Misstrauisch
      and Distanziert, Russian Отстранённый/Настороженный, Indonesian
      Ditinggalkan).
    - **Live run 1 (Dragón):** Spanish appears correctly. Palworld CANNOT
      change language mid-game, only between launches, so the "tags switch
      within 10 s" idea is moot (a comment was corrected). He saw a female Pal
      tagged "Curioso".
    - **GENDER (2026-09-18, his catch):** in es, pt, fr, it, pl and ru an
      entry is now `{ m = , f = }` (75 of them: tags, plus the joined,
      betrayed, fell, abandoned and shaken messages where a word or pronoun
      changes). `Locale.T(key, { female = })` picks the form; unknown or
      None gender uses the masculine (the neutral form in those languages).
      The gender comes from `UPalIndividualCharacterParameter:GetGenderType()`
      (EPalGenderType: 0 None, 1 Male, 2 Female). Personality reads it ONCE
      into its record (`state.female`, `Personality.IsFemale(palId)`) for the
      tags; Capture reads it at message time (`Capture.IsFemale(pal)`), the
      join resolves it before the capture like the name, and Trust caches it
      with the name for a follower that later despawns. localetest D2.
      Live run 2 (Dragón): female and male forms show correctly.
    - **Review file for Dragón (2026-09-18):** he wants every text checked by
      other AIs and translators. `docs/translations-review.md` is GENERATED
      from Locale.lua by `tools/translations/` (see its README): context,
      rules for reviewers, and one table per language. Corrections come back
      by ID, then regenerate. Pending: his reviewers' feedback, which may
      change strings before or after 1.1.5.
    - **REVIEW APPLIED (2026-09-18).** Dragón had ChatGPT and Gemini review
      the file (`docs/reveiw-chatgpt.txt`, `docs/review-gemini.txt`, his
      files; the first name is his typo). Weighed against my own pass and
      against his descriptions, 26 replacements in Locale.lua:
      - tr Feral Azgın → Gözü dönmüş (sexual meaning; not Vahşileşmiş,
        which contains "wild"; not Yırtıcı, which may clash with the
        Predator Pals);
      - pl Feral → Wściekły/Wściekła; id Scarred → Sakit hati; ja Curious
        → 好奇心旺盛; ko Curious → 호기심 많음;
      - fr Scarred → Trahi/Trahie (not "Blessé", which reads as injured
        under a health bar); fr and it shaken keep the flinch (now
        gendered in fr);
      - id abandoned → "berhenti menunggumu" (ChatGPT's "menyerah padamu"
        could mean "surrendered to you"); tr "Terk edilmiş"; fr "en
        arrière";
      - es shaken → "Su confianza en ti flaquea" (Dragón's pick over his
        own "se derrumba", which describes the betrayal rather than the
        warning); es joined stays "decidió irse contigo" (he felt
        "acompañarte" reads like following);
      - Russian → informal ты everywhere. Dragón left it to me: he wanted
        the mod to read casually, even though his Russian description uses
        вы.
      Rejected: German "Ein wilder Pal"/"Er" (his German description uses
      neuter "das Pal", so the current text matches it), and renaming the
      F10 system in de/pl/ru/ja/ko (those are his descriptions' own terms).
      22 suites pass; deployed; the review file was regenerated.
      `dump_locale.js` now resolves its fengari path.
    - Live language checks (Dragón): every language looked right; the
      longer Russian tags still fit the Pal card.
    - **50% "following" toast (Dragón's idea, 2026-09-18):** "{name} seems
      to like you and starts following you." It is his phrase plus a
      clause saying what the Pal now does. 24th string, all 16 sets
      (gendered in pl, ru, it). `Capture.NotifyStartedFollowing(name,
      female)`, positive tone. Both routes into following go through
      `on_became_bonded` in Trust.lua: StartFollowing, AND crossing 50%
      during the 20% calm-down. That second route previously never cached
      the name, so a later despawn toast would have said "A Pal"; fixed.
      pointstest P3/P12.
    - Order after every interaction: 50% check, then 20% (only for Pals not
      following), then 100%. So a single interaction that crosses 50% skips
      the calm-down (following already calms), and one that reaches 100%
      starts the follow and then joins after the usual 5 s. **Dragón's call
      (2026-09-18): when the same interaction reaches 100%, NO "starts
      following" message, only the join message**
      (`Trust.StartFollowing(pal, st, ratio, quiet)`). The follow itself
      still starts, unchanged. pointstest P5.
    - Settings text, from Dragón's questions: JoinBonus now says 200000 is
      the game's highest rank and the maximum accepted (above that: ignored,
      default used, reported). The chances are explained as weights with a
      worked example (Curious 100 + Aloof 100 + the other five at defaults
      = 260 in total, each about 38%). His old settings file (it lacked
      Language) was deleted; the next launch writes the current one.
    - My own second-pass suggestions (2026-09-18, superseded by the applied review above; weigh them
      together with his reviewers'): id tag_scarred Terluka → Sakit Hati
      (physical, a real error); tr tag_abandoned → "Terk edilmiş", tag_hostile
      → Saldırgan, tag_friendly → Dost canlısı, fell "düştü" → "yenik düştü";
      pl tag_feral → Wściekły/Wściekła, tag_scarred → Zraniony/Zraniona; fr
      abandoned "laissé derrière" → "laissé en arrière"; es shaken 2nd
      sentence → "Su confianza en ti flaquea." Flagged for natives: tr "Bağlı",
      ko 당신, ja noun/adjective mix in tags.
    - **Palworld's own languages (`EPalLanguageType`, Pal_enums.hpp:2822):
      JP, EN, ZH_HANS, ZH_HANT, FR, IT, DE, ES, KO, PT_BR, RU, TH, VI, ID, TR,
      PL, ES_MX.** That is exactly Dragón's 16 Workshop translations plus
      English. Where the game stores the current choice is not found yet
      (no ini holds it; `EditorPlayTextLanguageType` is editor-only).
- **OWN POINTS REWORK — Dragón's rulings (2026-09-18), next work:**
  - The bar runs on PalBonds' own points, not the game's `FriendshipPoint`.
    Every existing number carries over: base bar 500 × level tier
    (×4/×2/×1.5/×1/×0.75/×0.5/×0.25) × 2 for bosses; 20% Friendly/forgive, 50%
    bonded, 100% joins; Pet 50, Play 50, Feed 50 + rarity 10..50, lesser
    Peach 250, Peach 500; passive +2 per 1.5 s while following (stays as is,
    and becomes a setting later); a player hit below 50% drops to 0; a bonded
    hit costs half the bar, and reaching 0 is betrayal; drift past 30 m for
    3 s means all trust is lost.
  - **Removed:** the −150 when something other than the player hits a
    follower. "Since we now make the pals fight together this shouldn't exist
    anymore."
  - **Join bonus: only the flat +50,000** of the game's real trust. The old
    raise-to-21,000 (`CAPTURE_BONUS_TARGET_POINT` in Trust.lua) goes; Dragón
    didn't know it still existed. The +50,000 becomes a setting later.
  - Play's backup branch (`INTERACTION_FRIENDSHIP_GAIN` 25, which skips the
    fled check) moves onto the one grant path at 50. That's a bug fix.
  - The README wording "hit a bonded Pal and it's over" overstates the rule
    (the first hit costs half the bar). Fix the wording.
  - Check what happens to the bars after a save and reload before building on
    it.
  - **IMPLEMENTED 2026-09-18, awaiting Dragón's live run.** In `mod/` and the
    game copy (DEBUG_LOGGING true); not released.
    - Trust.lua: `st.points` in `State`, plus `Trust.GetPoints`,
      `Trust.AddPoints` (refuses owned Pals, clamps at 0) and
      `Trust.GetBarRatio`. OnInteractionSucceeded, the brief-follow end check,
      unbonded hit (→0), bonded hit (−half bar, then betrayal →0), drift (→0)
      and passive (+2) all use it.
    - Removed: `CAPTURE_BONUS_TARGET_POINT` (the rank-3 raise),
      `CAPTURE_AT_FRIENDSHIP_POINT`, `DAMAGE_FRIENDSHIP_PENALTY` (the −150 was
      already unreachable from both hooks since pass 211; its dead branch is
      gone), `Trust.GetBondingThreshold`, `Trust.ComputeBondingThresholdFor`
      (old F9), `lastPoint`/`lastRank`.
    - Interaction.lua: Pet/Play (`grant_wild_interaction`) and Feed (the
      RequestUseToCharacter post-hook) grant through `Trust.AddPoints`. Play's
      backup branch uses the same path at 50 (`INTERACTION_FRIENDSHIP_GAIN`
      removed). Log tags: `[BALANCE-TEST] ... trust a -> b` and
      `[FEED-FRIENDSHIP] wild Feed +n, trust a -> b`.
    - Indicator.lua: `get_friendship_ratio` is now `Trust.GetBarRatio`, one
      name lookup instead of three reflection calls per bar refresh.
    - The game's friendship is now written ONLY by Capture.OnTrustMaxed's flat
      +50,000.
    - **Bug fixed along the way (was in 1.1.4):** `local briefFollow` was
      declared below `Trust.ResetForNewWorld`, so the reset wrote a stray
      global and never cleared the real calm-down table on a world change. It
      is now declared next to `State`.
    - Tests: the new `tools/harness/pointstest.js` (P1–P9 plus a source scan;
      it fails on 1.1.4, including the stray global). bosstest was moved onto
      `Trust.GetPoints`/`GetBarRatio`. All 19 suites pass.
    - Still to do at release: README.md/README.txt wording (the bonded hit
      costs half the bar first); DEBUG_LOGGING back to false.
  - **Despawned Pals are forgotten (Dragón, 2026-09-18):** "the pals are still
    wild so on world reload or even by teleporting away they should despawn
    and that's fine, those don't need to be recorded unless still inside the
    radius of the player area - so let them despawn normally, no need to save
    their data." That answers the 09-16 open question "keep or wipe an invalid
    Pal's trust": wipe it. Implemented: `forget_despawned_pals()` at the top of
    every Trust tick drops any NON-following record whose actor is invalid
    (along with its level cache, drift clock and brief-follow entry), logged
    `[DESPAWN]`. Tested in pointstest P10.
    - **Followers, Dragón 2026-09-18: "if a pal despawn lets show the
      abandoned toast".** Implemented. A bonded follower whose actor goes
      invalid gets its record dropped, `Combat.ForgetDespawnedFollower(key)`
      (every per-follower table dropped by key, with nothing called on the
      dead actor; `forget_follower_tables` is now shared with StopFollowing),
      and `Capture.NotifyBondLostByName(st.displayName, "abandoned")`. The
      name is cached through `Capture.ResolveDisplayName` in
      `Trust.StartFollowing`. A Pal on its 20% calm-down is not bonded, so it
      is forgotten quietly. pointstest P10. This closes the 09-16 "despawn
      mid-countdown, skipped silently forever" bug.
    - Live run 2 (2026-09-18) confirmed: F10, a follower hit by an enemy costs
      nothing, `[DESPAWN]` for non-followers after teleporting, and a follower
      left behind by a teleport breaking through the normal drift path first.
  - **Betrayed Pal un-betrayed by a later hit (found in live run 1, present
    since 1.1.4), FIXED 2026-09-18:** after a betrayal (forced tier
    `warlike_anyway`), the player hitting the Pal again reached the below-50%
    rule, and RevertForgiveness put it back to its rolled personality. A
    naturally peaceful Pal would stop being angry after being betrayed.
    `OnFollowerDamaged` now returns early for `Capture.HasPermanentlyFled`.
    pointstest P11.
  - **Human NPCs can be petted but not fed. It has always been this way, and
    it is the game's own limit.** The wild feed calls
    `OnSelectedOrderWorkerRadialMenu`, which Pal.hpp declares on
    `APalMonsterCharacter` (Pals). Humans are `APalNPC`, its parent, so the
    call fails and the mod correctly grants nothing ("the wild feed did not go
    through"). Pet works because it goes through a different route.
    **Dragón's call: keep it as is.** "It's already plenty rare to interact
    with humans like that, just petting them is enough for now."
- **Today's work: polish the two held-back features** (20% brief follow and
  the 3000 self-defence reach) with live runs. The Workshop mods are off (no
  `ActiveModList` in `PalModSettings.ini`). The local dev copy is on again
  (`dwmapi.dll`, `enabled.txt`) with `mod/` + DEBUG_LOGGING true, and both
  switches set to **true in the game copy only**; `mod/` still has them false
  (= shipped 1.1.3). With the switches on, every harness test passes except
  bosstest G, which asserts the shipped (off) state.
  - Still to watch from run 5:
    - the release goes through `Combat.StopFollowing`, which can leave a
      self-trainer follow action on the wild Pal;
    - hitting the Pal during its brief follow counts as betrayal;
    - "no readable sensor, friendly preset not written".

**Real player reports to fold in (Steam Workshop, LuWicki97, read 2026-09-15):**
- *"been testing this with a friend via invite code. I befriended a digtoise
  and somehow my friend ended up getting it in his team instead."* That player
  concludes co-op isn't functional yet.
  - **Likely cause, unconfirmed:** every player lookup takes the FIRST valid
    `PalPlayerCharacter` in the object list. That was true of the old
    `FindAllOf`/`FindFirstOf` sites, and it is now true of `PlayerRef.Get()`.
    In co-op there are several, so the capture/grant can target another
    player.
  - A real fix needs "the player who interacted", e.g. from the hook context
    or the local controller, not "a player".
- *"often the options didn't pop up properly... tried on a lyleen and
  azurmane next. I didn't get an option at all."* Digtoise worked "somewhat
  fine". This may be the big-Pal targeting (aim sphere from the capsule, see
  `find_targeted_pal`), or it may be co-op-specific. Not reproduced yet.
- Dragón replied on the Workshop page (2026-09-15): the mod is only tested in
  singleplayer; for big Pals, aim at the lower body and get close.

**Multiplayer support (co-op worlds, community dedicated servers): analysed
2026-09-12, not started.** Dragón asked what it would take. Official Pocketpair
servers do not allow mods at all, so that is not a goal. For player-hosted co-op
worlds and modded community servers, the host/server simulates wild Pals' AI,
hate, friendship and capture, and the mod was written for one local player:
- every player lookup takes the first player found (Trust, Combat, Capture,
  Interaction, Personality);
- bonding state is per Pal with no owner, so two players cannot bond separately;
- input is local (F8/F9/F10 keybinds, radial-menu hooks) while trust grants
  (`AddFriendShip`, ~22 call sites), follow/combat actions and capture only take
  effect on the server, and UE4SS Lua has no networking of its own, so client
  requests would have to ride on game RPCs the server already receives;
- trust bars and tags are client-side UI and would need server values;
- a dedicated server has no local player at all, and Workshop mods on dedicated
  servers are Windows-only with every client needing the same mods.
Likely today, untested: the host of a co-op world gets the mod for themselves;
guests do not. Cheapest first step if pursued: a co-op session with a friend,
both with the mod, to see what already works, then decide whether a real
client/server split is worth it. It is a large rework of the "who" logic in
four modules, not a patch.

**Play's cheer emote — SHIPPED.** Cheer is `BP_Action_Emote_0_C` (Dragón
identified it with the F7 probe, which has since been removed). Played as the
last statement of `do_play`, logs `[EMOTE]` only on failure.

**Hotkeys fire while typing in chat — DECLINED, do not propose again.** The
Kick Keybind reference mod caches `PalEditableTextBox` /
`PalMultiLineEditableTextBox` / `EditableTextBox` and checks
`HasKeyboardFocus()` before acting; this project's F8/F9/F10 binds have no such
guard. Dragón, 2026-09-14: F8/F9/F10 are "hardly touched during typing," so
fixing this isn't necessary. Left here only as a historical note of the
mechanism, in case the calculus changes later.


**Play's target-busy gate — do not fix in isolation.** Dragón's call, 2026-09-11:
*"lets skip it for now, but add it as a pending for when the play interaction
gets its full development, right now there's no need to fix something thats
just an added extra"*.

The problem, so it does not need re-diagnosing later: `do_play` gates on the
TARGET's `ActionComponent:ActionIsEmpty()`, and a wild Pal almost always has
some idle action running, so the gate refuses nearly every press. His
2026-09-11 log shows **4 out of 4 F8 presses refused** on it, every one having
found its Pal correctly:

```
19:40:57  F8 pressed — starting Play
19:40:57  target is busy or its action state couldn't be read — skipping Play
```

`ActionIsEmpty()` is the signal this project has already rejected twice as
unreliable (it broke the rest animation in pass 179 and defeated three separate
capture-delay attempts, because it reports empty in the gaps between steps of a
real multi-part action). So the fix is not to tweak the gate — it is to decide
what "the target is available" actually means, as part of giving Play a real
implementation. Play also still has no radial-menu entry, which Dragón wants;
these belong in the same piece of work.

## Next steps

**This is the ONLY list that says what is open.** Everything in "Pending,
deliberately deferred" and in the dated sections above is narrative history:
read it to learn HOW something was solved, never to decide WHAT is open. Dragón
had to correct exactly that mistake on 2026-09-28 — a "STILL OPEN" line from
2026-09-19 was reported back to him as current work, twenty lines above the
section recording that it had shipped in 1.1.6. Keeping this list honest is
Claude's own job, not a question for him.

**Open and agreed:**
1. **Releasing bonded Pals back into the wild.** Swordfish's request, the only
   unbuilt feature request left. Dragón has called it "an extra out of scope from
   this project", so the timing is his — but it is genuinely open, and he
   confirmed it again on 2026-09-28 as the one item on that list he agrees with.
2. **Performance polish**, under his standing rule "the idea is that we polish it
   as much as we can". The named costs are defect 6 below. The route he has been
   shown, and which every earlier win used, is to feed the work from hooks that
   already fire instead of sweeping the world — never to cut the feature.
3. **Doc and code housekeeping** (Claude's own, no input needed): this file's
   lists kept current, closed items closed, `CLAUDE.md` archived before it
   outgrows a single read again, and the 1.1.9 zip rebuilt whenever 1.2.0 is
   packaged (the release-tree README is deliberately ahead of it).
4. **Store descriptions:** a TRIM planned around 1.2.0, not an addition. Dragón
   finished the Workshop translations himself on 2026-09-28.

**Open, but waiting on somebody else — do not chase:**
5. **Hakaishin Beerus' crash.** The only crash report never explained. They have
   been asked several times to open a GitHub issue and have not; Dragón's ruling
   stands — "we cant stop a whole proyect for 1 person". The trace build that
   would answer it is already public (GitHub pre-release `v1.1.6-test2` with
   `docs/crash-testing-guide.md`). Nothing to do until they act.
6. **Co-op, untested by anybody:** two real players at once, claims, a host who
   also plays, the dungeon resync. Needs a second person, not more code.

**CLOSED — do not re-list any of these as open work:**
- **Boss joins now count as defeated.** Solved in run 9, 2026-09-19, and shipped
  in 1.1.6: `ForceDamageDelegateForCaptureBall` registers the player as an
  attacker with no damage, so the GAME writes the defeat record and pays the
  first-kill reward itself — and refuses a second payout on a boss already
  beaten, which was Dragón's requirement.
- **The stuck waiting pose on a failed pet/feed.** Fixed through run 7
  (2026-09-19) and never seen again. Closed by Dragón, 2026-09-28: *"how do we
  chase something we cannot see? ... just close it already, we open new things if
  we find them."*
- **Esaeon's crash.** Theirs was the UE4SS build (`c838a8ac`); updating to
  `2281fa31` fixed every one with no PalBonds change.
- **Swordfish's crash.** Reported once as rare, against 1.1.5-era code, never
  mentioned again.
- **Microstutters** (1.1.2) and **the in-game settings screen** (1.1.9).
- **The three gameplay hotkeys on `RegisterKeyBind`.** NOT work. Dragón's ruling,
  2026-09-28: it has never been reproduced by anyone, the three crash reports it
  was theorised from are each explained or stale, and a matching error code is
  not a matching bug. Do not propose fixing a crash that exists only as a theory.
- **Bonded Pals despawning when you travel far.** A KNOWN LIMITATION, stated as
  such in the store descriptions. Dragón, 2026-09-28: *"unless something
  completely new arises, there's no goal here ... there's no real way to fix it
  without breaking the flow of the mod."* Do not reopen it with old ideas.

Deliberately NOT next: the AI-controller swap (see "Two routes to the right
brain") — a fallback only, and the current approach works.

## KNOWN LIMITATION: bonded wild Pals despawn when you travel far — parked 2026-09-14

Dragón's call after a long, thorough investigation: *"i think we will leave
this as a known limitation that maybe in a future with a fresh mind we can
fix."* **None of the code from that investigation shipped.** The whole
experimental tree is preserved at
`stale/2026-09-14_despawn-investigation-scripts/` if any of it is ever wanted
again; the release build is clean v1.1.0 plus only the owned-Pal tag fix.

### What the symptom actually is

A bonded (following, not yet captured) Pal vanishes once the player travels
far enough from where she was bonded. She is **not** drifting, **not** being
abandoned, and the player does **not** need to teleport or change maps.
Dragón watched it happen directly, many times, while she was following
normally right beside him.

### What is now CONFIRMED, with evidence

1. **The despawn is a gameplay call, not engine streaming.**
   `UPalCharacterManager::DespawnCharacterByHandle` was hooked read-only and
   caught the real call live, on a Pal being tracked, `isFollowing=true`.
2. **Distance from the player is irrelevant.** Measured at the moment of
   death across three separate runs: **978**, **1564**, and ~1500 units —
   ordinary following range every time.
3. **She is in the persistent level; only her SPAWNER is in a streamed cell.**
   ```
   Pal:     .../PL_MainWorld5.PL_MainWorld5:PersistentLevel.BP_FlowerDoll_C_...
   Spawner: .../PL_MainWorld5/_Generated_/MainGrid_L0_X-7_Y6_...:PersistentLevel.BP_PalSpawner_..._UAID_...
   ```
   Cell streaming destroys the spawner; gameplay code then despawns the Pals
   that spawner owned. (Confirmed against Epic's World Partition docs:
   runtime-spawned actors in the persistent level are not unloaded by cell
   streaming.)
4. **The spawner object is rebuilt fresh on every visit.** Two probes at the
   same landmark, before and after travelling away, returned the same class
   and grid cell but different instance suffixes (`..._1932335164` vs
   `..._1932343169`).
5. **Her identity SURVIVES the despawn.** At +3s and +15s after the despawn
   call: `handle valid=true, parameter readable=true, friendship=74` (and 60
   for a second Pal). The `UPalIndividualCharacterHandle`, the
   `UPalIndividualCharacterParameter` and her real accumulated friendship all
   outlive the actor. **This is the most promising fact for any future fix.**
6. **No live actor remains.** `TryGetIndividualActor` returns a Lua wrapper
   around a NULL UObject (`actorIsValid=false`, location unreadable) — the
   same null-wrapper trap `Personality.lua`'s header already documents.

### Dead ends — do NOT re-run these

- **`RemoveGroupCharacter` at bond time** (detach her from the spawner's wild
  group). Ran clean, returned ok, changed nothing. The wild GROUP list and the
  spawner's SPAWNED-handle list (`GetAllSpawnedNPCHandle`) are different
  things, and despawn travels by handle, not by group.
- **Periodic re-homing to the nearest spawner** (`AddGroupCharacterByGroupId`,
  then `AddGroupCharacter`). Worked exactly as designed — correct wild-Pal
  spawners, correct remove-then-add sequencing, tracked her across 4+ grid
  cells over 2 minutes — and she still despawned. Logical group membership
  does not protect the actor.
- **Home-radius mitigation** (stop her before she reaches the danger zone,
  with a toast). Built and working, but **rejected by Dragón for a real
  design flaw**: the radius is anchored to wherever the player stood when
  bonding started, not to the zone's actual centre, so a player who bonds
  near a corner still loses her well inside the "safe" budget. *"which will
  eventually lead to players still finding the pals can despawn."*
- **Blocking the despawn call from Lua.** Not possible: UE4SS's Lua
  `RegisterHook` has no cancel/veto (verified against the official docs and
  the Palworld modding wiki — return values can be overridden, execution
  cannot be skipped).

### Two crashes came out of this, same signature — read before trying again

`EXCEPTION_ACCESS_VIOLATION reading address 0x0000000000000048`, twice,
both immediately around `AddGroupCharacterByGroupId`. The second one was
pinpointed exactly: the log's final line was the "removing from previous
spawner" message with no matching "re-homed to" line after it. The constant
across both was that function's third parameter — an `FString DebugName`
being **constructed fresh from a Lua literal** and passed into a native call.
That is the same root-cause category as this project's older "Crash #4"
(`docs/hook-points-archive.md`). Switching to the plain
`AddGroupCharacter(handle)` — no string, no constructed value — stopped the
crashes completely. **Standing rule reinforced: never build a value from
scratch in Lua to hand into a native call if a no-argument variant exists.**

### If this is picked up again, start here

The identity surviving (point 5) is the whole opportunity. The route is
`UPalCharacterManager::SpawnCharacterByHandle(Handle, FNetworkActorSpawnParameters, callback)`
— respawn the SAME individual, with her real trust intact, rather than
preventing the despawn at all. Two cautions:
- `FNetworkActorSpawnParameters` is a 0x78 struct containing an `FName` and a
  `TSubclassOf<AController>`. **Omit the `FName` rather than construct one** —
  a zeroed field is `NAME_None`, which is safer than the conversion that
  caused both crashes.
- Its `ControllerClass` field is interesting on its own: a respawn through it
  could in principle bring her back running `BP_MonsterAIController_Otomo_C`,
  the "right brain" this project has wanted since the controller finding.
- A simpler-looking alternative, `UPalOtomoHolderComponentBase::ActivatePalByHandle(Handle, FVector, FRotator, bool)`,
  needs no risky parameters at all, but is the Otomo-holder path and most
  likely requires her to be party-owned — the early-capture trade-off Dragón
  has already declined twice.


## Where the real detail lives

`docs/hook-points.md` is the technical log, pass by pass, with the exact class
and function names and what each experiment proved. It is the file to search
when you need to know whether something was already tried. `CLAUDE-archive.md`
holds the older narrative history. `DESIGN.md` holds the original design; note
that its §12 "Priority TODO list" is marked SUPERSEDED and should not be used to
judge current state — **check the code, not the planning docs.**

