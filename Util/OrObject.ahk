#Requires AutoHotkey v2.0

/************************************************************************
 * @class OrObject
 * @brief Modificación de la clase Object que indexa sus propiedades por
 * orden de creación.
 * 
 * @note Funciona como la clase Object nativa, la única desventaja es que 
 * no se puede inicializar directamente con `{}`. Para conseguir una 
 * funcionalidad similar se debe utilizar su constructor.
 * 
 * @author bitasuperactive
 * @date 19/12/2025
 * @version 1.0.0
 * @extends Object
 * @see https://github.com/bitasuperactive/ahk2-excel-library/blob/master/Util/OrObject.ahk
 ***********************************************************************/
class OrObject extends Object
{
    /**
     * @private
     * Nombres de las propiedades por orden de creación.
     */
    _props := [] ;

    /**
     * @public
     * Crea un nuevo objeto cuyas propiedades serán indexadas.
     * @param {Any} props Cada propiedad se asigna con 2 parámetros,
     * un String que será el nombre, y cualquier tipo para el valor.
     * @returns {OrObject}
     */
    __New(props*)
    {
        evenProps := Mod(props.Length, 2) = 0
        if (!evenProps)
            throw ValueError("Propiedades inválidas.")
        
        for key in props {
            evenIndex := Mod(A_Index, 2) = 0
            if (evenIndex)
                continue
            if (Type(key) != "String" || InStr(key, ' '))
                throw ValueError("Propiedades inválidas.")

            val := props[A_Index + 1]
            this.%key% := val
        }
        
        return this
    }

    /**
     * @public
     * @see https://www.autohotkey.com/docs/v2/lib/Object.htm#DefineProp
     */
    DefineProp(name, desc)
    {
        this._props.Push(name)
        return super.DefineProp(name, desc)
    }

    /**
     * @public
     * @see https://www.autohotkey.com/docs/v2/lib/Object.htm#DeleteProp
     */
    DeleteProp(name)
    {
        index := this._HasProp(name)
        if (index > 0)
            this._props.RemoveAt(index)
        
        return super.DeleteProp(name)
    }

    /**
     * @public
     * Enumera las propiedades adquiridas del objeto por orden
     * de creación.
     * @returns {Enumerator}
     * @see https://www.autohotkey.com/docs/v2/lib/Object.htm#OwnProps
     */
    OwnProps()
    {
        props := this._props.Clone()
        return (&k := "", &v := "") => __Iterate(&k, &v)


        __Iterate(&k, &v)
        {
            if (A_Index > props.Length)
                return false

            k := props[A_Index]
            v := this.%k%
            return true
        }
    }

    /**
     * @private
     * @see https://www.autohotkey.com/docs/v2/Objects.htm#Meta_Functions
     */
    __Set(name, params, value)
    {
        if (name = "_props")
            super.DefineProp(name, { Value: value })
        else
            this.DefineProp(name, { Value: value })
        
        return value
    }

    /**
     * @private
     * Comprueba si la propiedad está definida en el array.
     * @param {String} prop Nombre de la propiedad objetivo.
     * @returns {Integer} Índice de la propiedad, o 0 si no la encuentra.
     */
    _HasProp(prop)
    {
        for p in this._props {
            if (p = prop)
                return A_Index
        }
        return 0
    }
}