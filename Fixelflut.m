#import <ObjFW/ObjFW.h>
#import <ObjFW/OFTCPSocket.h>
#import <ObjFW/OFString.h>
#import <ObjFW/OFAutoreleasePool.h>
#import <ObjFW/OFStdIOStream.h>
#import <ObjFW/OFThread.h>

@interface Fixelflut: OFObject <OFApplicationDelegate>
@end

OF_APPLICATION_DELEGATE(Fixelflut)

//TODO move into own class
uint16_t canvas_width=100;
uint16_t canvas_height=100;
OFString* sizeString;

void killClient(OFTCPSocket* clientSocket, OFString* fault){
	[of_stdout writeFormat:@"Client send bullshit: %@\n", fault];
	[clientSocket writeLine: @"Error in format. Disconnecting"];
	[clientSocket close];
};

of_tcp_socket_async_accept_block_t acceptBlock = ^bool(OFTCPSocket* socket, OFTCPSocket* clientSocket, OFException* exception){
        
    if (exception) {
        [of_stdout writeFormat:@"Error: %@\n", exception];
        return false;
    }

    OFString* clientAddress = [clientSocket remoteAddress];
    [of_stdout writeFormat: @"New connection from %@\n", clientAddress];

	while(true){
		OFString* line = [clientSocket readLine];
		if(line != nil){
			if([line hasPrefix: @"PX "]){
				OFArray* components = [line componentsSeparatedByString: @" "];
				if([components count] != 4){
					killClient(clientSocket, line);
				}
				intmax_t x = [[components objectAtIndex: 1] decimalValue];
				intmax_t y = [[components objectAtIndex: 2] decimalValue];
				unsigned int r,g,b,a=255;
				OFString* color = [components objectAtIndex: 3];
				int length = [color length];
				intmax_t colorValue;
				if(length != 6  && length != 8){
					killClient(clientSocket, line);
					return true;
				}
				colorValue = [color hexadecimalValue];
				
				if(length == 8){
					r = colorValue >> 24 & 0xff;
					g = colorValue >> 16 & 0xff;
					b = colorValue >> 8 & 0xff;
					a = colorValue >> 0 & 0xff;
				}else{
					r = colorValue >> 16 & 0xff;
					g = colorValue >> 8 & 0xff;
					b = colorValue >> 0 & 0xff;
				}
				[of_stdout writeFormat:@"set %d, %d to 0x%02x 0x%02x 0x%02x 0x%02x\n", x, y, r,g,b,a];
				//TODO setPixel
			}
			else if([line isEqual: @"SIZE"]){
				[clientSocket writeLine: sizeString];
			}
			else{
				killClient(clientSocket, line);
				return true;
			}
		}//TODO detect discon
	}
    return true;
};


@implementation Fixelflut
- (void)applicationDidFinishLaunching
{
    // init Server
    OFTCPSocket* serverSocket = [OFTCPSocket socket];
    uint16_t port = [serverSocket bindToHost: @"0.0.0.0" port: 1337];
    
	sizeString = [[OFString alloc]initWithFormat: @"SIZE %d %d", canvas_width, canvas_height];
    [of_stdout writeFormat: @"Starting Server on port %d\n", port];
    [serverSocket listen];

    // register connection callback
    [serverSocket asyncAcceptWithBlock: acceptBlock];
    
	//[OFApplication terminate];
}
@end

