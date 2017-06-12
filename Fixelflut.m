#import <ObjFW/OFAutoreleasePool.h>
#import <ObjFW/OFStdIOStream.h>
#import <ObjFW/OFString.h>
#import <ObjFW/OFTCPSocket.h>
#import <ObjFW/OFThread.h>
#import <ObjFW/ObjFW.h>


// Include GLEW
#include <GL/glew.h>

// Include GLFW
#include <GLFW/glfw3.h>
GLFWwindow* window;

typedef struct {
  uint16_t x, y;
  uint8_t r;
  uint8_t g;
  uint8_t b;
  uint8_t a;
} __attribute__((packed)) fixelflutPackage;

@interface Backend:OFObject{
  uint16_t canvasHeight;
  uint16_t canvasWidth;
}
- (void)start;
- (void)setPixel: (fixelflutPackage*) pixel;
- (void)destroy;
@end

@implementation Backend:OFObject
- (void)start{};
- (void)setPixel: (fixelflutPackage*) pixel {};
- (void)destroy{};
@end

@interface RGBABackend : Backend
@end

@implementation RGBABackend
volatile unsigned char *pixeldata;

- (void)start{
  pixeldata = (unsigned char*) malloc(canvasWidth*canvasHeight*3);
	memset((void*)pixeldata, 0 ,canvasWidth*canvasHeight*3);
}
- (void)setPixel: (fixelflutPackage*) pixel {

  uint16_t x = pixel->x;
  uint16_t y = pixel->y;
  uint8_t  r = pixel->r;
  uint8_t  g = pixel->g;
  uint8_t  b = pixel->b;
  uint8_t  a = pixel->a;

  [of_stdout writeFormat:@"set %d, %d to 0x%02x 0x%02x 0x%02x 0x%02x\n", x, y, r, g, b, a];

  if (x >= canvasWidth || y >= canvasHeight)
    return;
  uint32_t position = 3 * y * canvasWidth + 3 * x;
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
@end

@interface GLBackend : RGBABackend
@end

@implementation GLBackend
- (void)start{
  [super start];
  // Initialise GLFW
	if( !glfwInit() )
	{
		fprintf( stderr, "Failed to initialize GLFW\n" );
		return;
	}

	const GLFWvidmode * mode = glfwGetVideoMode(glfwGetPrimaryMonitor());

	canvasWidth = mode->width;
	canvasHeight = mode->height;

	glfwWindowHint(GLFW_SAMPLES, 4);
	glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
	glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
	glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GL_TRUE); // To make MacOS happy; should not be needed
	glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);

	// Open a window and create its OpenGL context
	window = glfwCreateWindow( canvasWidth, canvasHeight, "Fixelflut", NULL, NULL);
	if( window == NULL ){
		fprintf( stderr, "Failed to open GLFW window.y\n" );
		glfwTerminate();
		return;
	}
	glfwMakeContextCurrent(window);
	//glfwSetWindowSizeCallback(window, window_size_callback);

	// Initialize GLEW
	glewExperimental = true; // Needed for core profile
	if (glewInit() != GLEW_OK) {
		fprintf(stderr, "Failed to initialize GLEW\n");
		return;
	}

	// Ensure we can capture the escape key being pressed below
	glfwSetInputMode(window, GLFW_STICKY_KEYS, GL_TRUE);

	// Dark black background
	glClearColor(0.0f, 0.0f, 0.0f, 0.0f);

  do{
    glfwSwapBuffers(window);
	  glfwPollEvents();
	} // Check if the ESC key was pressed or the window was closed
	while( glfwGetKey(window, GLFW_KEY_ESCAPE ) != GLFW_PRESS &&
		   glfwWindowShouldClose(window) == 0 );
}
@end

@interface Fixelflut : OFObject <OFApplicationDelegate>{
  OFTCPSocket* _serverSocket;
  OFString* _sizeString;
  Backend* _backend;  
}
- (uint16_t)startServer:(of_tcp_socket_async_accept_block_t)callback;
- (uint16_t)startServerWithPort:(uint16_t)port
                       callback:(of_tcp_socket_async_accept_block_t)callback;
@end

OF_APPLICATION_DELEGATE(Fixelflut)

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
          fixelflutPackage f;
          f.x = x;
          f.y = y;
          f.r = r;
          f.g = g;
          f.b = b;
          f.a = a;
          [_backend setPixel: &f];
        } else if ([line isEqual:@"SIZE"]) {
          [clientSocket writeLine: self._sizeString];
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
  [_backend setPixel: fixel];
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

  _backend = [GLBackend alloc];
  [_backend start];
}

- (uint16_t)startServerWithPort:(uint16_t)port
                       callback:(of_tcp_socket_async_accept_block_t)callback {

  _serverSocket = [[OFTCPSocket alloc] init];
  uint16_t realPort = [_serverSocket bindToHost:@"0.0.0.0" port:port];

  _sizeString = [[OFString alloc]
      initWithFormat:@"SIZE %d %d", _backend->canvasWidth, _backend->canvasHeight];
  [of_stdout writeFormat:@"Starting Server on port %d\n", realPort];
  [_serverSocket listen];

  // register connection callback
  [_serverSocket asyncAcceptWithBlock:callback];
  [_serverSocket asyncAcceptWithTarget: self
				       selector: @selector(OF_socket:
						     didAcceptSocket:
						     exception:)];
  return realPort;
}

- (uint16_t)startServer:(of_tcp_socket_async_accept_block_t)callback {
  return [self startServerWithPort:0 callback:callback];
}

- (void)stop
{
	[_serverSocket cancelAsyncRequests];
	[_serverSocket release];
	_serverSocket = nil;
}

@end
