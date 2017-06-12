// Include standard headers
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <pthread.h>
#include <errno.h>

// Include GLEW
#include <GL/glew.h>

// Include GLFW
#include <glfw3.h>
GLFWwindow* window;

// Include GLM
#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>
using namespace glm;

#include "shader.hpp"


volatile unsigned char* pixeldata;
uint16_t Xres,Yres;
uint16_t windowWidth = Xres, windowHeight = Yres;
GLuint Texture;

volatile int running = 1;
volatile int client_thread_count = 0;
volatile int server_sock;

float del = 2;
double lastTime = 0.0f;
int nbFrames = 0;


void set_pixel(uint32_t x, uint32_t y, char r, char g, char b, uint8_t a);

void FPS_init(float delay) {
    lastTime = glfwGetTime();
    nbFrames = 0;
    del = delay;
}

void FPS_count() {
    double currentTime = glfwGetTime();
    nbFrames++;
    if (currentTime - lastTime >= del) {
        float t = (currentTime - lastTime)*1000.0 / double(nbFrames);
        printf("%f ms/frame, %.1f frames / second\n", t, 1000.0f / t);
        nbFrames = 0;
        lastTime = glfwGetTime();
    }
}

void createTexture(){
	pixeldata = (unsigned char*) malloc(Xres*Yres*3);
	memset((void*)pixeldata, 0 ,Xres*Yres*3);

	glGenTextures(1, &Texture);

	// "Bind" the newly created texture : all future texture functions will modify this texture
	glBindTexture(GL_TEXTURE_2D, Texture);

	// Give the image to OpenGL
	glTexImage2D(GL_TEXTURE_2D, 0,GL_RGB, Xres, Yres, 0, GL_RGB, GL_UNSIGNED_BYTE, (void*)pixeldata);

	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);

}

void updateTexture(){
	glBindTexture(GL_TEXTURE_2D, Texture);
	glInvalidateTexImage(Texture, 0);

	glTexImage2D(GL_TEXTURE_2D, 0,GL_RGB, Xres, Yres, 0, GL_RGB, GL_UNSIGNED_BYTE, (void*)pixeldata);

	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
}

void window_size_callback(GLFWwindow* window, int width, int height) {
	glfwMakeContextCurrent(window);
	glViewport(0, 0, width, height);
	windowWidth = width;
	windowHeight = height;
}

GLuint TextureID;
GLuint programID;
GLuint MatrixID;
GLuint vertexbuffer;
GLuint uvbuffer;
GLuint VertexArrayID;
glm::mat4 MVP;

int initGraphics(const char* name){
// Initialise GLFW
	if( !glfwInit() )
	{
		fprintf( stderr, "Failed to initialize GLFW\n" );
		return -1;
	}

	const GLFWvidmode * mode = glfwGetVideoMode(glfwGetPrimaryMonitor());

	Xres = mode->width;
	Yres = mode->height;

	glfwWindowHint(GLFW_SAMPLES, 4);
	glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
	glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
	glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GL_TRUE); // To make MacOS happy; should not be needed
	glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);

	// Open a window and create its OpenGL context
	window = glfwCreateWindow( Xres, Yres, name, NULL, NULL);
	if( window == NULL ){
		fprintf( stderr, "Failed to open GLFW window.y\n" );
		glfwTerminate();
		return -1;
	}
	glfwMakeContextCurrent(window);
	glfwSetWindowSizeCallback(window, window_size_callback);

	// Initialize GLEW
	glewExperimental = true; // Needed for core profile
	if (glewInit() != GLEW_OK) {
		fprintf(stderr, "Failed to initialize GLEW\n");
		return -1;
	}

	// Ensure we can capture the escape key being pressed below
	glfwSetInputMode(window, GLFW_STICKY_KEYS, GL_TRUE);

	// Dark black background
	glClearColor(0.0f, 0.0f, 0.0f, 0.0f);

	// Enable depth test
	glEnable(GL_DEPTH_TEST);
	// Accept fragment if it closer to the camera than the former one
	glDepthFunc(GL_LESS); 

	glGenVertexArrays(1, &VertexArrayID);
	glBindVertexArray(VertexArrayID);

	// Create and compile our GLSL program from the shaders
	programID = LoadShaders( "vertexshader", "fragmentshader" );

	// Get a handle for our "MVP" uniform
	MatrixID = glGetUniformLocation(programID, "MVP");

	// Projection matrix : 45° Field of View, 4:3 ratio, display range : 0.1 unit <-> 100 units
	glm::mat4 Projection = glm::ortho(-1.0f, 1.0f, -1.0f ,1.0f, 0.1f, 100.0f);
	// Camera matrix
	glm::mat4 View       = glm::lookAt(
								glm::vec3(1,0,0), // Camera is at (4,3,3), in World Space
								glm::vec3(0,0,0), // and looks at the origin
								glm::vec3(0,0,1)  // Head is up (set to 0,-1,0 to look upside-down)
						   );
	// Model matrix : an identity matrix (model will be at the origin)
	glm::mat4 Model      = glm::mat4(1.0f);
	// Our ModelViewProjection : multiplication of our 3 matrices
	MVP = Projection * View * Model; // Remember, matrix multiplication is the other way around

	createTexture();
	
	// Get a handle for our "myTextureSampler" uniform
	TextureID = glGetUniformLocation(programID, "myTextureSampler");

	// Our vertices. Tree consecutive floats give a 3D vertex; Three consecutive vertices give a triangle.
	// A cube has 6 faces with 2 triangles each, so this makes 6*2=12 triangles, and 12*3 vertices
	static const GLfloat g_vertex_buffer_data[] = { 
		-1.0f,-1.0f,-1.0f,
		-1.0f,-1.0f, 1.0f,
		-1.0f, 1.0f, 1.0f,
		-1.0f, 1.0f, 1.0f,
		-1.0f, 1.0f,-1.0f,
		-1.0f,-1.0f,-1.0f,
	};

	// Two UV coordinatesfor each vertex. They were created withe Blender.
	static const GLfloat g_uv_buffer_data[] = { 
		0.0, 1.0, 
		0.0, 0.0, 
		1.0, 0.0, 
		1.0, 0.0, 
		1.0, 1.0,
		0.0, 1.0,
	};

	glGenBuffers(1, &vertexbuffer);
	glBindBuffer(GL_ARRAY_BUFFER, vertexbuffer);
	glBufferData(GL_ARRAY_BUFFER, sizeof(g_vertex_buffer_data), g_vertex_buffer_data, GL_STATIC_DRAW);

	
	glGenBuffers(1, &uvbuffer);
	glBindBuffer(GL_ARRAY_BUFFER, uvbuffer);
	glBufferData(GL_ARRAY_BUFFER, sizeof(g_uv_buffer_data), g_uv_buffer_data, GL_STATIC_DRAW);
}

void drawPixels(){
	
	// Clear the screen
	glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

	// Use our shader
	glUseProgram(programID);

	// Send our transformation to the currently bound shader, 
	// in the "MVP" uniform
	glUniformMatrix4fv(MatrixID, 1, GL_FALSE, &MVP[0][0]);



	// Bind our texture in Texture Unit 0
	glActiveTexture(GL_TEXTURE0);
	glBindTexture(GL_TEXTURE_2D, Texture);
	updateTexture();
	// Set our "myTextureSampler" sampler to user Texture Unit 0
	glUniform1i(TextureID, 0);
	
	// 1rst attribute buffer : vertices
	glEnableVertexAttribArray(0);
	glBindBuffer(GL_ARRAY_BUFFER, vertexbuffer);
	glVertexAttribPointer(
		0,                  // attribute. No particular reason for 0, but must match the layout in the shader.
		3,                  // size
		GL_FLOAT,           // type
		GL_FALSE,           // normalized?
		0,                  // stride
		(void*)0            // array buffer offset
	);

	// 2nd attribute buffer : UVs
	glEnableVertexAttribArray(1);
	glBindBuffer(GL_ARRAY_BUFFER, uvbuffer);
	glVertexAttribPointer(
		1,                                // attribute. No particular reason for 1, but must match the layout in the shader.
		2,                                // size : U+V => 2
		GL_FLOAT,                         // type
		GL_FALSE,                         // normalized?
		0,                                // stride
		(void*)0                          // array buffer offset
	);

	// Draw the triangle !
	glDrawArrays(GL_TRIANGLES, 0, 2*3); // 12*3 indices starting at 0 -> 12 triangles

	glDisableVertexAttribArray(0);
	glDisableVertexAttribArray(1);

	// Swap buffers
	glfwSwapBuffers(window);
	glfwPollEvents();
}

void deleteGraphics(){

	// Cleanup VBO and shader
	glDeleteBuffers(1, &vertexbuffer);
	glDeleteBuffers(1, &uvbuffer);
	glDeleteProgram(programID);

	glDeleteTextures(1, &TextureID);
	glDeleteVertexArrays(1, &VertexArrayID);

	// Close OpenGL window and terminate GLFW
	glfwTerminate();
}


void set_pixel(uint32_t x, uint32_t y, char r, char g, char b, uint8_t a)
{
	uint32_t position = 3 * y * Xres + 3 * x;
	if(a == 255){
		pixeldata[position + 0] = r;
		pixeldata[position + 1] = g;
		pixeldata[position + 2] = b;
	}else{
		float alpha = ((float)a)/255.0f;
		pixeldata[position + 0] *= 1-alpha;
		pixeldata[position + 1] *= 1-alpha;
		pixeldata[position + 2] *= 1-alpha;
		pixeldata[position + 0] += r*alpha;
		pixeldata[position + 1] += g*alpha;
		pixeldata[position + 2] += b*alpha;
	}
}

ssize_t readLine(int fd, char* buf, size_t n)
{
    ssize_t numRead;                    
    size_t totRead;                    
    char ch;

    if (n <= 0 || buf == NULL) {
        return -1;
    }

    totRead = 0;
    for (;;) {
        numRead = read(fd, &ch, 1);

        if (numRead == -EINTR) {
		continue;
        } else if(numRead < 0){
		return -1;   
	}else if (numRead == 0) {     
            if (totRead == 0)           
                return 0;
            else                        
                break;
        } else {                       
            if (totRead < n - 1) {
                totRead++;
                *buf++ = ch;
            }

            if (ch == '\n')
                break;
        }
    }

    *buf = '\0';
    return totRead;
}

void *pixelflut_handler(void *socket_desc)
{
    //Get the socket descriptor
    int sock = *(int*)socket_desc;
    int read_size;
    char *message , client_message[4096];

    const char* size_str = "SIZE\n";
    const char* px_header_str = "PX ";

    while(readLine(sock, client_message, 4096) > 0){
	if(!strncmp(client_message, size_str, strlen(size_str))){
		char response[200];
		sprintf(&response[0], "SIZE %d %d", windowWidth, windowHeight);
		int ret = write(sock , response , strlen(response));
		if(ret < 0){
			printf("Write failed");			
		}
		printf("Wrote size command\n");
	}
	else if(!strncmp(client_message, px_header_str, strlen(px_header_str))){
		unsigned int x, y, color;
		unsigned int r,g,b,a=255;

		char* next;
		unsigned  int length= strlen(client_message);
		x = strtol(client_message+2, &next, 10);
		y = strtol(next+1, &next, 10);
		unsigned int rest = strlen(next);
		color = strtol(next+1, &next, 16);
		//without alpha
		if(rest == 8){
			r = color >> 16 & 0xff;
			g = color >> 8 & 0xff;
			b = color >> 0 & 0xff;
		}else if(rest == 10){
			r = color >> 24 & 0xff;
			g = color >> 16 & 0xff;
			b = color >> 8 & 0xff;
			a = color >> 0 & 0xff;
		}else{
			break;
		}

		if(x >= Xres || y >= Yres) continue;
		set_pixel(x, y, r,g,b,a);
	}
    }
     
    if(read_size == 0)
    {
        puts("Client disconnected");
        fflush(stdout);
    }
    else if(read_size == -1)
    {
        perror("recv failed");
    }
         
    return 0;
}

typedef struct {
  uint16_t x, y;
  uint8_t r;
  uint8_t g;
  uint8_t b;
  uint8_t a;
} __attribute__((packed)) fixelflut;

void *fixelflut_handler(void *socket_desc)
{
    //Get the socket descriptor
    int sock = *(int*)socket_desc;
    char client_message[100];

    int ret = 0;
    uint32_t res = (Xres << 16) | Yres;
    write(sock, &res, sizeof(res));

    while((ret = read(sock, client_message, sizeof(fixelflut))) > 0){
	if(ret < sizeof(fixelflut)) break;
	
	fixelflut* cmd = (fixelflut*) client_message;
	
	if(cmd->x >= Xres || cmd->y >= Yres) continue;
	set_pixel(cmd->x, cmd->y, cmd->r,cmd->g,cmd->b,cmd->a);
    }
} 

void* fixelflut_server(void * foobar){
    int socket_desc , client_sock , c;
    struct sockaddr_in server , client;
     
    //Create socket
    socket_desc = socket(AF_INET , SOCK_STREAM , 0);
    if (socket_desc == -1)
    {
        printf("Could not create socket");
    }
    puts("Fixelflut Socket created");
     
    //Prepare the sockaddr_in structure
    server.sin_family = AF_INET;
    server.sin_addr.s_addr = INADDR_ANY;
    server.sin_port = htons( 2345 );
	    
    int foo = 1;
    setsockopt(socket_desc, SOL_SOCKET, SO_REUSEADDR, &foo, sizeof(foo));
    
    //Bind
    if(bind(socket_desc,(struct sockaddr *)&server , sizeof(server)) < 0)
    {
        //print the error message
        perror("bind failed. Error");
        return NULL;
    }
    puts("bind done");
     
    //Listen
    listen(socket_desc , 3);
     
    //Accept and incoming connection
    puts("Waiting for incoming connections...");
    c = sizeof(struct sockaddr_in);
	pthread_t thread_id;
	
    while( (client_sock = accept(socket_desc, (struct sockaddr *)&client, (socklen_t*)&c)) )
    {
        puts("Connection accepted");
         
        if( pthread_create( &thread_id , NULL ,  fixelflut_handler , (void*) &client_sock) < 0)
        {
            perror("could not create thread");
            return NULL;
        }

        puts("Handler assigned");
    }
     
    if (client_sock < 0)
    {
        perror("accept failed");
        return NULL;
    }
}

void* pixelflut_server(void * foobar){
    int socket_desc , client_sock , c;
    struct sockaddr_in server , client;
     
    //Create socket
    socket_desc = socket(AF_INET , SOCK_STREAM , 0);
    if (socket_desc == -1)
    {
        printf("Could not create socket");
    }
    puts("Socket created");
     
    //Prepare the sockaddr_in structure
    server.sin_family = AF_INET;
    server.sin_addr.s_addr = INADDR_ANY;
    server.sin_port = htons( 1234 );
	    
    int foo = 1;
    setsockopt(socket_desc, SOL_SOCKET, SO_REUSEADDR, &foo, sizeof(foo));
    
    //Bind
    if(bind(socket_desc,(struct sockaddr *)&server , sizeof(server)) < 0)
    {
        //print the error message
        perror("bind failed. Error");
        return NULL;
    }
    puts("bind done");
     
    //Listen
    listen(socket_desc , 3);
     
    //Accept and incoming connection
    puts("Waiting for incoming connections...");
    c = sizeof(struct sockaddr_in);
	pthread_t thread_id;
	
    while( (client_sock = accept(socket_desc, (struct sockaddr *)&client, (socklen_t*)&c)) )
    {
	struct sockaddr_in* in = (struct sockaddr_in*) &client;
	struct in_addr* addr = &in->sin_addr;
	unsigned char* caddr = (unsigned char*)&addr->s_addr;
        printf("Connection accepted from %d.%d.%d.%d\n", caddr[0], caddr[1], caddr[2], caddr[3]);
         
        if( pthread_create( &thread_id , NULL ,  pixelflut_handler , (void*) &client_sock) < 0)
        {
            perror("could not create thread");
            return NULL;
        }

        puts("Handler assigned");
    }
     
    if (client_sock < 0)
    {
        perror("accept failed");
        return NULL;
    }
}

void createPixelflutServerThread(){

	pthread_t thread_id;
	if(pthread_create(&thread_id , NULL, pixelflut_server , NULL) < 0){
		perror("could not createServerThread");
	}
}

void createFixelflutServerThread(){

	pthread_t thread_id;
	if(pthread_create(&thread_id , NULL, fixelflut_server , NULL) < 0){
		perror("could not createServerThread");
	}
}

int main(int argc, char** argv)
{
	const char* name = "Fixelflut";
	if(argc == 2) name = argv[1];
	initGraphics(name);
	createPixelflutServerThread();
	createFixelflutServerThread();
 	FPS_init(2);
	do{
		drawPixels();
		FPS_count();
	} // Check if the ESC key was pressed or the window was closed
	while( glfwGetKey(window, GLFW_KEY_ESCAPE ) != GLFW_PRESS &&
		   glfwWindowShouldClose(window) == 0 );

	deleteGraphics();
	delete(pixeldata);
	return 0;
}

