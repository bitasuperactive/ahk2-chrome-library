#Requires AutoHotkey v2.0

/************************************************************************
 * @brief Permite registrar, lanzar y eliminar eventos.
 * @author bitasuperactive
 * @date 25/12/2025
 * @version 1.0.1
 * @see https://github.com/bitasuperactive/ahk2-excel-library/blob/master/Util/EventController.ahk
 ***********************************************************************/
class EventController
{
    /** @private */
    _events := Map() ;

    /**
     * @public
     * Mapa de los nombres de los eventos y las colecciones de llamadas asociadas.
     * @type {Map<String, Array<Func>>}
     */
    Events => this._events ;

    /**
     * @public
     * Registra o elimina una llamada para un evento.
     * 
     * - No duplica callbacks para un mismo evento.
     * 
     * @param {String} name Nombre del evento.
     * @param {Func} callback Llamada a ejecutar. Si su valor es `0`, 
     * se eliminan todos los callbacks asociados al evento.
     */
    OnEvent(name, callback)
    {
        if (callback = 0) {
            if (this._events.Has(name)) {
                this._events.Delete(name)
            }
            return
        }
        if !(callback is Func)
            throw TypeError("Se esperaba una función, pero se ha recibido: " Type(callback))

        if (!this._events.Has(name)) {
            this._events[name] := [callback]
        }
        else if (!__IsCallbackSet(this._events[name], callback)) {
            this._events[name].Push(callback)
        }
        

        __IsCallbackSet(arr, val)
        {
            for v in arr {
                if (v = val)
                    return true
            }
            return false
        }
    }

    /**
     * @public
     * Dispara todos los callbacks registrados para un evento.
     * @param {String} name Nombre del evento.
     * @param {Any} params Cualesquiera parámetros para los callbacks.
     */
    Trigger(name, params*)
    {
        for callback in this._events.Get(name, []) {
            ;// Los métodos siempre están ligados a un objeto "this" (Binding)
            callback(this, params*)
        }
    }

    /**
     * @public
     * Desecha todos los eventos configurados.
     */
    Dispose()
    {
        this._events := Map()
    }
}