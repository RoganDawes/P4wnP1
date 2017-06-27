##############
# Method implementation
##############
$methodclass = New-Object psobject -Property @{
    id = $null
    name = $null
    started = $null
    finished = $null
    args = $null
    result = $null
    error = $null
    error_message = $null
}

$methodclass | Add-Member -Force -MemberType ScriptMethod -Name "setResult" -Value {
    param(
          [Parameter(Mandatory=$true)]
          [Byte[]] $result
    )

    # the result has to be a byte array

    if ($result -eq $null)
    {
        # this is an Error
        $errstr = "Method {0} was called, but returned nothing" -f $this.name
        $this.setError($errstr)

        return
    }

    # check if result could be converted to Byte[] should already been done (parameter is forced to [Byte[]])



    $this.result = $result
    $this.finished = $true
}

$methodclass | Add-Member -Force -MemberType ScriptMethod -Name "setError" -Value {
    param(
          [Parameter(Mandatory=$true)]
          [String] $error_message
    )

    $host.UI.WriteErrorLine($error_message) # only for debug purpose

    $this.error_message = $error_message
    $this.finished = $true
    $this.error = $true
}

$methodclass | Add-Member -Force -MemberType ScriptMethod -Name "parseRequest" -Value {
    param(
          [Parameter(Mandatory=$true)]
          [Byte[]] $request
    )


    # extract ID of method call (used as reference when asyncronous response is sent)
    $METHOD_ID, $remaining = $structclass.extractUInt32($request)
 
    # extract method name and args (args = remainder)
    $METHOD_NAME, $remaining = $structclass.extractNullTerminatedString($remaining)

    # extract method args
    $METHOD_ARGS = $remaining
                    
    $method.id = $METHOD_ID
    $method.name = $METHOD_NAME
    $method.args = $METHOD_ARGS
}

$methodclass | Add-Member -Force -MemberType ScriptMethod -Name "createResponse" -Value {
    param(
          [Parameter(Mandatory=$true)]
          [Byte[]] $request
    )

    # this function should only be called when the method has finished (finished member == $true), but anyway, this isn't checked her

    # first field is uint32 method id
    $response = $structclass.packUInt32($this.id)

    # next field is a ubite indicating success or error (0 success, everything else error)
    if ($this.error) 
    {
        $response = $structclass.packByte(1, $response) # indicating an error
        $response = $structclass.packString($this.error_message, $response) #append error message

        return $response # hand back error response
    }

    $response = $structclass.packByte(0, $response) # add success field
    
    return [Byte[]] ($response + $this.result) # return result
}



function MethodFromRequest {
    param(
          [Parameter(Mandatory=$true)]
          [Byte[]]$request
    )
    
    $method = $methodclass.psobject.Copy()

    # initial values
    $method.parseRequest($request)
    $method.finished = $false # ToDo: Thread safe access
    $method.started = $false # ToDo: Thread safe access
    $method.error = $false # ToDo: Thread safe access
    $method.error_message = "" # ToDo: Thread safe access

     # ToDo: Thread safe access for result
    
    
    return $method
}




function Method {
    param(
          [Parameter(Mandatory=$true)]
          [uint32]$id, # ID of method (to connect response to request)

          [Parameter(Mandatory=$true)]
          [String]$name, 

          #[Parameter(Mandatory=$true)]
          #[bool]$started,

          #[Parameter(Mandatory=$true)]
          #[bool]$finished,

          [Parameter(Mandatory=$true)]
          [Byte[]]$args

          #[Parameter(Mandatory=$true)]
          #[Byte[]]$result
    )
    
    $method = $methodclass.psobject.Copy()

    # initial values
    $method.id = $id
    $method.name = $name
    $method.args = $args
    $method.finished = $false # ToDo: Thread safe access
    $method.started = $false # ToDo: Thread safe access
    $method.error = $false # ToDo: Thread safe access
    $method.error_message = "" # ToDo: Thread safe access

     # ToDo: Thread safe access for result
    
    
    return $method
}
##############
# End Methos implementation
##############
