##############
# Channel implementation for TransportLayer
##############
$channelclass = New-Object psobject -Property @{
    id = 0
    encoding = 0
    type = 0
    _in_queue = $null
    _out_queue = $null

    TYPE_IN = 1
    TYPE_OUT = 2
    TYPE_BIDIRECTIONAL = 3

    ENCODING_UTF8 = 1
    ENCODING_BYTEARRAY = 2
}

$channelclass | Add-Member -Force -MemberType ScriptMethod -Name "write" -Value {
    param(
          [Parameter(Mandatory=$true)]
          $data
    )

    if ($this.type -eq $channelclass.TYPE_IN)
    {
        $Host.UI.WriteErrorLine("Channel with ID {0} isn't writable" -f $this.id)
    }

    if ($this.encoding -eq $this.ENCODING_BYTEARRAY)
    {
        if (($data.GetType()).IsSubclassOf([Array])) {
            # $data is of type Array, so we try to convert to Byte[]
            $data = [Byte[]] $data
        }
        else
        {
            $Host.UI.WriteErrorLine("Channel write: Wrong data type provided, should be Byte[] or Object[] for this encoding ")
            return
        }
        
    }
    elseif ($this.encoding -eq $this.ENCODING_UTF8)
    {
        if ($data.GetType() -eq [String]) {
            # $data is of type String, so we try to convert to Byte[]
            $data = [System.Text.Encoding]::UTF8.GetBytes($data)
        }
        else
        {
            $Host.UI.WriteErrorLine("Channel write: Wrong data type provided, should be String for this encoding ")
            return
        }
    }

    # push data to outbound queue
    $this._out_queue.Enqueue($data)
}


$channelclass | Add-Member -Force -MemberType ScriptMethod -Name "read" -Value {
    if ($this.type -eq $channelclass.TYPE_OUT)
    {
        $Host.UI.WriteErrorLine("Channel with ID {0} isn't readable" -f $this.id)
    }

    if ($this._in_queue.Count -eq 0)
    {
        # no data
        return $null
    }

    $data = $this._in_queue.Dequeue()

    if ($this.encoding -eq $this.ENCODING_BYTEARRAY)
    {
        return [Byte[]] $data
    }
    elseif ($this.encoding -eq $this.ENCODING_UTF8)
    {
        $data = [System.Text.Encoding]::UTF8.GetString($data)
        return $data
    }
}

$channelclass | Add-Member -Force -MemberType ScriptMethod -Name "hasPendingInData" -Value {
    return $this._in_queue.Count
}

$channelclass | Add-Member -Force -MemberType ScriptMethod -Name "hasPendingOutData" -Value {
    return $this._out_queue.Count
}

function Channel {
    param(
          [Parameter(Mandatory=$true)]
          [uint32]$id, # P4wnP1 internal channel ID (exists on both peers)

          # out: sends data from this client to the server (the same channel id is a in channel on the server)
          # in: receives data from the server (the same channel is an out channel on the server)
          [Parameter(Mandatory=$true)]
          [Byte]$type, # in = 1, out = 2, bidir = 3 

          [Parameter(Mandatory=$true)]
          [Byte]$encoding # UTF-8 = 1, Byte[] = 2
    )
    
    $ch = $channelclass.psobject.Copy()

    # initial values
    $ch.id = $id
    $ch.encoding = $encoding
    $ch.type = $type

    if (($type -eq 1) -or ($type -eq 3)) {
        # in or bidirectional type, create input_queue
        $ch._in_queue = [System.Collections.Queue]::Synchronized((New-Object System.Collections.Queue))
    }

    if (($type -eq 2) -or ($type -eq 3)) {
        # out or bidirectional type, create output_queue
        $ch._out_queue = [System.Collections.Queue]::Synchronized((New-Object System.Collections.Queue))
    }

    return $ch
}
##############
# End channel implementation for TransportLayer
##############
