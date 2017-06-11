#import <ObjFW/OFAutoreleasePool.h>
#import <ObjFW/OFStdIOStream.h>
#import <ObjFW/OFString.h>
#import <ObjFW/OFTCPSocket.h>
#import <ObjFW/OFThread.h>
#import <ObjFW/ObjFW.h>

typedef struct {
  uint16_t x, y;
  uint8_t r;
  uint8_t g;
  uint8_t b;
  uint8_t a;
} __attribute__((packed)) fixelflutPackage;

@interface Fixelflut : OFObject <OFApplicationDelegate>
- (uint16_t)startServer:(of_tcp_socket_async_accept_block_t)callback;
- (uint16_t)startServerWithPort:(uint16_t)port
                       callback:(of_tcp_socket_async_accept_block_t)callback;
@end

OF_APPLICATION_DELEGATE(Fixelflut)

// TODO move into own class?
volatile unsigned char *pixeldata;
uint16_t canvas_width = 100;
uint16_t canvas_height = 100;
OFString *sizeString;

void setPixel(uint32_t x, uint32_t y, uint8_t r, uint8_t g, uint8_t b,
              uint8_t a) {
  [of_stdout writeFormat:@"set %d, %d to 0x%02x 0x%02x 0x%02x 0x%02x\n", x, y,
                         r, g, b, a];

  if (x >= canvas_width || y >= canvas_height)
    return;
  uint32_t position = 3 * y * canvas_width + 3 * x;
  if (a == 255) {
    pixeldata[position + 0] = r;
    pixeldata[position + 1] = g;
    pixeldata[position + 2] = b;
  } else {
    float alpha = ((float)a) / 255.0f;
    pixeldata[position + 0] *= 1 - alpha;
    pixeldata[position + 1] *= 1 - alpha;
    pixeldata[position + 2] *= 1 - alpha;
    pixeldata[position + 0] += r * alpha;
    pixeldata[position + 1] += g * alpha;
    pixeldata[position + 2] += b * alpha;
  }
}

void blameClient(OFTCPSocket *clientSocket, OFString *fault) {
  [of_stdout writeFormat:@"Client send bullshit: %@\n", fault];
  [clientSocket writeLine:@"Error in format. Disconnecting"];
};

of_stream_async_read_line_block_t lineHandleBlock =
    ^bool(OFStream *stream, OFString *line, OFException *exception) {
      if (line != nil) {
        OFTCPSocket *clientSocket = (OFTCPSocket *)stream;
        if ([line hasPrefix:@"PX "]) {
          OFArray *components = [line componentsSeparatedByString:@" "];
          if ([components count] != 4) {
            blameClient(clientSocket, line);
            return false;
          }
          intmax_t x = [[components objectAtIndex:1] decimalValue];
          intmax_t y = [[components objectAtIndex:2] decimalValue];
          unsigned int r, g, b, a = 255;
          OFString *color = [components objectAtIndex:3];
          int length = [color length];
          intmax_t colorValue;
          if (length != 6 && length != 8) {
            blameClient(clientSocket, line);
            return false;
          }
          colorValue = [color hexadecimalValue];

          if (length == 8) {
            r = colorValue >> 24 & 0xff;
            g = colorValue >> 16 & 0xff;
            b = colorValue >> 8 & 0xff;
            a = colorValue >> 0 & 0xff;
          } else {
            r = colorValue >> 16 & 0xff;
            g = colorValue >> 8 & 0xff;
            b = colorValue >> 0 & 0xff;
          }
          setPixel(x, y, r, g, b, a);
        } else if ([line isEqual:@"SIZE"]) {
          [clientSocket writeLine:sizeString];
        } else {
          blameClient(clientSocket, line);
          return false;
        }
      }
      return true;
    };

of_stream_async_read_block_t fixelHandleBlock = ^bool(
    OFStream *stream, void *buffer, size_t length, OFException *exception) {
  if (exception) {
    [of_stdout writeFormat:@"Error: %@\n", exception];
    return false;
  }

  fixelflutPackage *fixel = (fixelflutPackage *)buffer;
  setPixel(fixel->x, fixel->y, fixel->r, fixel->g, fixel->b, fixel->a);
  return true;
};

of_tcp_socket_async_accept_block_t acceptPixelflutBlock = ^bool(
    OFTCPSocket *socket, OFTCPSocket *clientSocket, OFException *exception) {

  if (exception) {
    [of_stdout writeFormat:@"Error: %@\n", exception];
    return false;
  }

  OFString *clientAddress = [clientSocket remoteAddress];
  [of_stdout writeFormat:@"New Pixelflut connection from %@\n", clientAddress];

  [clientSocket asyncReadLineWithBlock:lineHandleBlock];

  return true;
};

of_tcp_socket_async_accept_block_t acceptFixelflutBlock = ^bool(
    OFTCPSocket *socket, OFTCPSocket *clientSocket, OFException *exception) {

  if (exception) {
    [of_stdout writeFormat:@"Error: %@\n", exception];
    return false;
  }

  OFString *clientAddress = [clientSocket remoteAddress];
  [of_stdout writeFormat:@"New Fixelflut connection from %@\n", clientAddress];

  struct fixelflutPackage *f = malloc(sizeof(fixelflutPackage));
  [clientSocket asyncReadIntoBuffer:f
                        exactLength:sizeof(fixelflutPackage)
                              block:fixelHandleBlock];

  return true;
};

@implementation Fixelflut

// main logic
- (void)applicationDidFinishLaunching {
  // init Server
  [self startServerWithPort:1234 callback:acceptPixelflutBlock];
  [self startServerWithPort:2345 callback:acceptFixelflutBlock];
}

- (uint16_t)startServerWithPort:(uint16_t)port
                       callback:(of_tcp_socket_async_accept_block_t)callback {
  OFTCPSocket *serverSocket = [OFTCPSocket socket];
  uint16_t realPort = [serverSocket bindToHost:@"0.0.0.0" port:port];

  sizeString = [[OFString alloc]
      initWithFormat:@"SIZE %d %d", canvas_width, canvas_height];
  [of_stdout writeFormat:@"Starting Server on port %d\n", realPort];
  [serverSocket listen];

  // register connection callback
  [serverSocket asyncAcceptWithBlock:callback];
  return realPort;
}

- (uint16_t)startServer:(of_tcp_socket_async_accept_block_t)callback {
  return [self startServerWithPort:0 callback:callback];
}
@end
