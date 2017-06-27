##########################
# TransportLayer implementation
##########################

# TL only forwards messages in current implementation
# but would be able to modify every stream if needed 
# (maybe needed for scheduling when socket channels come into play)

$transportlayerclass = New-Object psobject -Property @{
    _ll = $null
    _inChannels = $null
    _outChannels = $null
    _ctrl_ch = $null
    nextChannelID = [uint32]1 #channel ID 0 is reserved for CONTROL communication on transportlayer
}

$transportlayerclass | Add-Member -Force -MemberType ScriptMethod -Name "CreateChannel" -Value {
    param(
          [Parameter(Mandatory=$true)]
          [Byte]$type, # in = 1, out = 2, bidir = 3 (out means the channel sends data from this client to the server)

          [Parameter(Mandatory=$true)]
          [Byte]$encoding # UTF-8 = 1, Byte[] = 2
    )

    # create channel object
    $ch = Channel -encoding $encoding -type $type -id $this.nextChannelID
    $this.nextChannelID = $this.nextChannelID + 1
    
    # add object to channel lists (out and/or in)
    if ($ch._in_queue) { $this._inChannels.([String]$ch.id) = $ch }
    if ($ch._out_queue) { $this._outChannels.([String]$ch.id) = $ch }

    # return channel
    return $ch
}


$transportlayerclass | Add-Member -Force -MemberType ScriptMethod -Name "GetChannel" -Value {
    param(
          [Parameter(Mandatory=$true)]
          [uint32]$ch_id
    )

    # check if channel exists in input channels
    if ($this._inChannels.Contains([String] $ch_id))
    {
        return $this._inChannels.([String] $ch_id)
    }

    # check if channel exists in output channels
    if ($this._outChannels.Contains([String] $ch_id))
    {
        return $this._outChannels.([String] $ch_id)
    }
    
    return $null
}

$transportlayerclass | Add-Member -Force -MemberType ScriptMethod -Name "Clear" -Value {
    # clear queues if present
    if ($his._in_queue) { $this._in_queue.Clear() }
    if ($his._out_queue) { $this._out_queue.Clear() }
}


$transportlayerclass | Add-Member -Force -MemberType ScriptMethod -Name "ProcessOutSingle" -Value {
    # single iteration of Output processing (needs to be called in a loop)
    
    # ToDo: foreach iteration needs to be checked for thread safety (adding/removing channels while iterating)
    $keys = $tl._outChannels.Keys
    foreach ($key in $keys) {
        # try to fetch cannel (f not deleted meanwhile)
        $ch = $null
        if ($tl._outChannels.ContainsKey($key))
        {
            $ch = $tl._outChannels.$key
        }
        else
        {
            $Host.UI.WriteErrorLine("Channel $key doesn't exist ... delted while iterating ?")
        }

 
        # check if theres pending output in channel queue
        # The "while" could be replaced by an "if" to send only one enqueued message and go on with the next channel
        while ($ch._out_queue.Count -gt 0) {
            # send data via link layer
            ##########################
            # if fragmentation is needed it should be implemented here (load balancing between channels)

            # dequeue data
            $data = $ch._out_queue.Dequeue()

            # convert channel ID to uint32 in network order
            $ch_id = [BitConverter]::GetBytes([uint32]$ch.id)
            # account for endianess (Convert to network order)
            if ([System.BitConverter]::IsLittleEndian) {
                [array]::Reverse($ch_id) # not needed as this is zero
            }

            # add channel ID to data to create a complete stream
            $stream = [Byte[]] ($ch_id + $data)

            # add stream to LinkLayer out queue
            $this._ll.PushOutputStream($stream)
        }
    }
}

$transportlayerclass | Add-Member -Force -MemberType ScriptMethod -Name "hasData" -Value {
    if ($this._ll.PendingInputStreamCount())
    {
        return $true
    }
    return $false
}

$transportlayerclass | Add-Member -Force -MemberType ScriptMethod -Name "waitForData" -Value {
    $this._ll.WaitForInputStream()
}

$transportlayerclass | Add-Member -Force -MemberType ScriptMethod -Name "getData" -Value {
    return $this._ll.PopPendingInputStream()
}

$transportlayerclass | Add-Member -Force -MemberType ScriptMethod -Name "ProcessInSingle" -Value {
    param(
          [Parameter(Mandatory=$true)]
          [bool]$blockIfNoData
    )
    
    # single iteration of Input processing (needs to be called in a loop)

    if ($blockIfNoData) 
    {
        $this.waitForData() # blocking wait, till input stream arrives
    }

    while ($this._ll.PendingInputStreamCount()) # as long as link layer has data
    {

        # pop next stream
        $stream = $this._ll.PopPendingInputStream()
        #handle_request -stream $stream

        # extract channel ID and remaining payload
        $ch_id, $data = $structclass.extractUInt32($stream)



        Remove-Variable stream

        # push data to target channel (but not if output channel)
        $target_ch = $this.GetChannel($ch_id)
        if ($target_ch.type -ne $channelclass.TYPE_OUT)
        {
            $target_ch._in_queue.Enqueue($data)
        }
        else
        {
            $Host.UI.WriteErrorLine("Data received for channel id {0}. Data is ignored, as this is an output channel" -f $target_ch.id)
        }
        

        
    }
}


$transportlayerclass | Add-Member -Force -MemberType ScriptMethod -Name "write_control_channel" -Value {
    param(
          [Parameter(Mandatory=$true)]
          [Byte[]]$data
    )

    # push data to outbound queue of control channel (id 0)
    $ctrl_ch = $this._ctrl_ch._out_queue.Enqueue($data)
}


function TransportLayer {
    param(
          [Parameter(Mandatory=$true)]
          [PSCustomObject]$LinkLayer

    )
    
    $tl = $transportlayerclass.psobject.Copy()

    # initial values
    $tl._ll = $LinkLayer
    $tl._inChannels = [hashtable]::Synchronized(@{})
    $tl._outChannels = [hashtable]::Synchronized(@{})

    # create control channel (ID 0)
    $ctrl_ch = Channel -encoding $channelclass.ENCODING_BYTEARRAY -type $channelclass.TYPE_BIDIRECTIONAL -id 0
    $tl._inChannels.([String]0) = $ctrl_ch
    $tl._outChannels.([String]0) = $ctrl_ch
    $tl._ctrl_ch = $ctrl_ch

    # return TransportLayer object
    return $tl
}


############
# End TransportLayer
########

