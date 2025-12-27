#Requires AutoHotkey v2.0

/************************************************************************
 * @brief
 * Clase que monitoriza la creación y eliminación de proceso individuales.
 * Para ello utiliza eventos WMI (`__InstanceCreationEvent` y `__InstanceDeletionEvent`)
 * sin bloquear el hilo principal.
 *
 * Esta clase se suscribe en modo asíncrono a WMI mediante `SWbemSink`,
 * ejecutando los callbacks indicados cuando el proceso objetivo aparece
 * o desaparece.
 * 
 * Ejemplo de uso:
 * @code
 * ProcessWMIWatcher("notepad.exe", ProcessWMIEventHandler((\*) => MsgBox("Proceso creado"), (\*) => MsgBox("Proceso terminado")))
 * @endcode
 * @author bitasuperactive
 * @date 17/12/2025
 * @version 1.0.0
 * @see https://github.com/bitasuperactive/ahk2-excel-library/blob/master/Util/ProcessWMIWatcher.ahk
 ***********************************************************************/
class ProcessWMIWatcher
{
    /**
     * @public
     * Establece un callback para la creación y destrucción del proceso indicado.
     * 
     * @warning Si la instancia no es liberada correctamente mediante `Dispose`, 
     * se pueden llegar a saturar los eventos WMI generando una infracción de cuotas.
     * 
     * @param {String} pName Nombre del proceso a escuchar (con extensión `.exe`).
     * @param {ProcessWMIEventHandler} handler Manejador para los eventos de ejecución y finalización del proceso.
     * @throws {Error} (0x8004106C) Si se produce una infracción de cuotas de WMI.
     */
    __New(pName, handler)
    {
        if (InStr(pName, ' ') || !InStr(pName, ".exe"))
            throw ValueError('El nombre del proceso "' pName '" no es válido.')
        if !(handler is ProcessWMIEventHandler)
            throw ValueError('Se requiere un EventHandler de la clase "' ProcessWMIEventHandler.Prototype.__Class '".')

        this.pName := pName
        this._wmi := ComObjGet("winmgmts:")
        this._sink := ComObject("WbemScripting.SWbemSink")
        ComObjConnect(this._sink, handler)
        
        command := "WITHIN 1  WHERE TargetInstance ISA 'Win32_Process' AND TargetInstance.Name = '" this.pName "'"
        this._wmi.ExecNotificationQueryAsync(this._sink, "SELECT * FROM __InstanceCreationEvent " command)
        this._wmi.ExecNotificationQueryAsync(this._sink, "SELECT * FROM __InstanceDeletionEvent " command)
            
        OnExit((*) => this.Dispose())
    }

    /**
     * @public
     * Cancela la suscripción a eventos WMI y desconecta el sink.
     */
    Dispose()
    {
        try ComObjConnect(this._sink)
        try this._sink.Cancel()
        try this._wmi.CancelAsyncCall(this._sink)
    }
}

/************************************************************************
 * @brief 
 * Clase encargada de gestionar los eventos WMI asociados a la creación y eliminación
 * de un proceso específico. Esta clase actúa como manejador (event sink) para los 
 * eventos enviados por WMI mediante el objeto `SWbemSink`. 
 * Se utiliza junto con `ProcessWMIWatcher`.
 * @author bitasuperactive
 * @date 26/12/2025
 * @version 1.0.1
 * @see https://github.com/bitasuperactive/ahk2-excel-library/blob/master/Util/ProcessWMIEventHandler.ahk
 ***********************************************************************/
class ProcessWMIEventHandler
{
    /**
     * @public
     * Crea un manejador para los eventos de WMI para ProcessWMIWatcher.
     * @param {Func<Boolean>} callback Función ejecutada al crearse o terminar un proceso.
     * Recibe un parámetro Boolean que será Verdadero si el proceso ha sido creado, o Falso
     * si ha sido finalizado.
     */
    __New(callback)
    {
        if (!(callback is Func) || callback.MinParams != 2)
            throw ValueError('El callback no es válido. Debe ser una función con un único parámetro obligatorio.')

        this._callback := callback
    }

    /**
     * @private
     * Método invocado automáticamente por WMI cuando ocurre un evento.
     * @param {SWbemObject} Obj Contiene la información del evento.
     */
    OnObjectReady(obj, *)
    {
        TI := obj.TargetInstance
        switch obj.Path_.Class
        {
            case "__InstanceCreationEvent":
            {
                this._callback(true)
            }
            case "__InstanceDeletionEvent":
            {
                ;// El número de procesos debe ser 0
                if (!ProcessExist(TI.Name))
                    this._callback(false)
            }
        }
    }
}